defmodule TrifleApp.OrganizationDeliveryLive do
  use TrifleApp, :live_view

  alias Trifle.Integrations
  alias Trifle.Organizations
  alias TrifleApp.OrganizationDeliveryLive.EmailComponent
  alias TrifleApp.OrganizationDeliveryLive.SlackComponent
  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Delivery options")
      |> assign(:breadcrumb_links, Navigation.breadcrumb(:delivery))
      |> assign(:active_tab, :delivery)
      |> assign(:current_user, current_user)
      |> assign(:can_manage, false)
      |> assign(:slack_info, nil)
      |> assign(:slack_installations, [])

    email_info = email_info()
    socket = assign(socket, :email_info, email_info)

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization/profile")}

      true ->
        {:ok, load_delivery_state(socket, membership)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <%= if @current_membership do %>
        <Navigation.nav active_tab={@active_tab} />

        <div class="flex flex-col gap-4">
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">
              Delivery Options
            </h2>
            <p class="mt-1 text-sm text-gray-600 dark:text-slate-300">
              Configure outbound delivery channels for this organization. References use the pattern <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs">@type#target</code>.
            </p>
            <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
              Future integrations will appear here as additional panels.
            </p>
          </div>

          <div class="space-y-4" id="delivery-integrations">
            <.live_component
              module={EmailComponent}
              id="email-integration"
              status={delivery_status(@email_info)}
              email_info={@email_info}
            />

            <.live_component
              module={SlackComponent}
              id="slack-integration"
              status={slack_status(@slack_info, @slack_installations)}
              slack_info={@slack_info}
              slack_installations={@slack_installations}
              can_manage={@can_manage}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event(
        "connect_slack",
        _params,
        %{assigns: %{slack_info: %{configured?: false}}} = socket
      ) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "Slack integration is not configured. Update the Helm values and redeploy."
     )}
  end

  def handle_event("connect_slack", _params, %{assigns: %{current_membership: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event(
        "connect_slack",
        _params,
        %{
          assigns: %{
            current_membership: membership,
            current_user: user,
            slack_info: %{configured?: true, settings: settings}
          }
        } = socket
      ) do
    if Organizations.membership_admin?(membership) do
      case build_slack_authorize_url(settings, membership, user) do
        {:ok, url} ->
          {:noreply, redirect(socket, external: url)}

        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "Only organization admins can manage Slack integrations.")}
    end
  end

  def handle_event("sync_slack", %{"id" => installation_id}, socket) do
    with %{} = membership <- socket.assigns.current_membership,
         true <- Organizations.membership_admin?(membership),
         %{} = installation <-
           Integrations.get_slack_installation(membership.organization_id, installation_id) do
      case Integrations.sync_slack_channels(installation) do
        {:ok, _updated} ->
          {:noreply,
           socket
           |> put_flash(:info, "Slack channels synced.")
           |> reload_slack_installations()}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Unable to sync Slack channels: #{format_reason(reason)}")}
      end
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Workspace not found. Refresh and try again.")}

      false ->
        {:noreply,
         socket
         |> put_flash(:error, "Only organization admins can manage Slack integrations.")}
    end
  end

  def handle_event(
        "toggle_slack_channel",
        %{"id" => channel_id, "next" => next_value},
        %{assigns: %{current_membership: membership}} = socket
      ) do
    with %{} = membership <- membership,
         true <- Organizations.membership_admin?(membership),
         {:ok, enabled} <- parse_boolean(next_value),
         {:ok, _channel} <-
           Integrations.update_slack_channel_enabled(
             membership.organization_id,
             channel_id,
             enabled
           ) do
      message =
        if enabled do
          "Channel enabled for delivery."
        else
          "Channel disabled for delivery."
        end

      {:noreply,
       socket
       |> put_flash(:info, message)
       |> reload_slack_installations()}
    else
      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Channel not found. Refresh and try again.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         put_flash(socket, :error, "Unable to update channel: #{changeset_error(changeset)}")}

      false ->
        {:noreply,
         socket
         |> put_flash(:error, "Only organization admins can manage Slack integrations.")}

      {:error, :invalid_boolean} ->
        {:noreply, put_flash(socket, :error, "Invalid channel state toggle.")}
    end
  end

  def handle_event(
        "remove_slack_installation",
        %{"id" => installation_id},
        %{assigns: %{current_membership: membership}} = socket
      ) do
    with %{} = membership <- membership,
         true <- Organizations.membership_admin?(membership),
         %{} = installation <-
           Integrations.get_slack_installation(membership.organization_id, installation_id),
         {:ok, _} <- Integrations.delete_slack_installation(installation) do
      {:noreply,
       socket
       |> put_flash(:info, "Slack workspace #{installation.team_name} disconnected.")
       |> reload_slack_installations()}
    else
      nil ->
        {:noreply, put_flash(socket, :error, "Workspace not found. Refresh and try again.")}

      false ->
        {:noreply,
         socket
         |> put_flash(:error, "Only organization admins can manage Slack integrations.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Unable to disconnect workspace: #{changeset_error(changeset)}"
         )}
    end
  end

  defp load_delivery_state(socket, membership) do
    email_info = email_info()
    slack_info = slack_info(membership.organization_id)
    can_manage = Organizations.membership_admin?(membership)

    slack_installations =
      Integrations.list_slack_installations_for_org(membership.organization_id,
        preload_channels: true
      )

    socket
    |> assign(:current_membership, membership)
    |> assign(:can_manage, can_manage)
    |> assign(:email_info, email_info)
    |> assign(:slack_info, slack_info)
    |> assign(:slack_installations, slack_installations)
  end

  defp email_info do
    mailer_config = Application.get_env(:trifle, Trifle.Mailer, [])
    adapter = extract_adapter(mailer_config)
    configured? = not is_nil(adapter) and adapter != Swoosh.Adapters.Local

    %{
      configured?: configured?,
      adapter: adapter,
      adapter_label: adapter_label(adapter),
      config: mailer_config
    }
  end

  defp extract_adapter(config) when is_list(config),
    do: Keyword.get(config, :adapter, Swoosh.Adapters.Local)

  defp extract_adapter(config) when is_map(config),
    do: Map.get(config, :adapter, Swoosh.Adapters.Local)

  defp extract_adapter(_), do: Swoosh.Adapters.Local

  defp adapter_label(nil), do: "unknown"
  defp adapter_label(Swoosh.Adapters.Local), do: "Local (dev mailbox)"

  defp adapter_label(adapter) when is_atom(adapter) do
    adapter
    |> Module.split()
    |> List.last()
  end

  defp adapter_label(value) when is_binary(value), do: value
  defp adapter_label(_), do: "custom"

  defp delivery_status(nil), do: :warning
  defp delivery_status(%{configured?: true}), do: :ok
  defp delivery_status(_), do: :warning

  defp slack_info(organization_id) do
    default_redirect = Integrations.default_slack_redirect_uri()
    settings = Integrations.slack_settings(default_redirect)
    configured? = Integrations.slack_configured?()

    %{
      configured?: configured?,
      settings: settings,
      organization_id: organization_id
    }
  end

  defp slack_status(nil, _installations), do: :warning

  defp slack_status(%{configured?: false}, _installations), do: :warning

  defp slack_status(_info, installations) do
    installations = installations || []

    cond do
      Enum.any?(installations, &slack_installation_error?/1) ->
        :error

      installations == [] ->
        :error

      true ->
        :ok
    end
  end

  defp slack_installation_error?(installation) do
    case Map.get(installation, :settings) do
      %{} = settings -> Map.get(settings, "error") in [true, "true", "1"]
      _ -> false
    end
  end

  defp reload_slack_installations(socket) do
    membership = socket.assigns.current_membership

    slack_installations =
      Integrations.list_slack_installations_for_org(membership.organization_id,
        preload_channels: true
      )

    assign(socket, :slack_installations, slack_installations)
  end

  defp build_slack_authorize_url(settings, membership, user) do
    client_id = blank_to_nil(settings.client_id)

    redirect_uri =
      blank_to_nil(settings.redirect_uri || Integrations.default_slack_redirect_uri())

    cond do
      is_nil(client_id) ->
        {:error, "Slack client ID is missing. Update the Helm values and redeploy."}

      is_nil(redirect_uri) ->
        {:error, "Slack redirect URI is missing. Update the Helm values and redeploy."}

      true ->
        state = Integrations.sign_slack_state(user.id, membership.organization_id)
        scopes = settings.scopes || Integrations.slack_default_scopes()

        params =
          %{
            "client_id" => client_id,
            "scope" => Enum.join(List.wrap(scopes), ","),
            "redirect_uri" => redirect_uri,
            "state" => state
          }
          |> URI.encode_query()

        {:ok, "https://slack.com/oauth/v2/authorize?" <> params}
    end
  end

  defp parse_boolean(value) when value in [true, "true", "1", 1], do: {:ok, true}
  defp parse_boolean(value) when value in [false, "false", "0", 0], do: {:ok, false}
  defp parse_boolean(_), do: {:error, :invalid_boolean}

  defp changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {_field, messages} -> messages end)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  defp format_reason({:slack_error, error}), do: error
  defp format_reason({:invalid_payload, reason}), do: format_reason(reason)
  defp format_reason({:missing_key, key}), do: "missing #{key}"
  defp format_reason({:error, reason}), do: format_reason(reason)
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value
end
