defmodule TrifleApp.OrganizationSSOLive do
  use TrifleApp, :live_view

  alias Ecto.Changeset
  alias Trifle.Organizations
  alias TrifleApp.OrganizationLive.Navigation
  alias TrifleApp.OrganizationSSOLive.GoogleComponent

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Single Sign-On")
      |> assign(:breadcrumb_links, Navigation.breadcrumb(:sso))
      |> assign(:active_tab, :sso)
      |> assign(:current_user, current_user)
      |> assign(:can_manage, false)
      |> assign(:organization, nil)
      |> assign(:sso_info, nil)
      |> assign(:google_sso_form, nil)
      |> assign(:show_google_sso_modal, false)

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization/profile")}

      true ->
        {:ok, load_sso_state(socket, membership)}
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
              Single Sign-On
            </h2>
            <p class="mt-1 text-sm text-gray-600 dark:text-slate-300">
              Manage Google Workspace SSO access for this organization.
            </p>
            <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
              Domains listed below will be auto-provisioned into this organization when users sign in with Google.
            </p>
          </div>

          <div class="space-y-4">
            <.live_component
              module={GoogleComponent}
              id="google-sso-panel"
              status={google_sso_status(@sso_info)}
              sso_info={@sso_info}
              can_manage={@can_manage}
            />
          </div>
        </div>
      <% end %>
    </div>

    <.app_modal
      id="google-sso-modal"
      show={@show_google_sso_modal}
      on_cancel="close_google_sso_modal"
      size="lg"
    >
      <:title>Manage Google SSO</:title>
      <:body>
        <.form :if={@google_sso_form} for={@google_sso_form} phx-submit="save_google_sso" class="space-y-5">
          <.form_field
            type="checkbox"
            field={@google_sso_form[:enabled]}
            label="Enable Google sign-in"
            help="When disabled, Google OAuth logins are blocked for this organization."
          />

          <.form_field
            type="checkbox"
            field={@google_sso_form[:auto_provision_members]}
            label="Automatically add members"
            help="When enabled, users from approved domains are added to the organization on their first Google login."
          />

          <.form_field
            type="textarea"
            field={@google_sso_form[:domains]}
            label="Allowed Google Workspace domains"
            help="Enter one domain per line, e.g. example.com. Domains must be unique across all organizations."
            class="min-h-[120px]"
          />

          <.form_actions>
            <.primary_button phx-disable-with="Saving...">Save changes</.primary_button>
            <.secondary_button type="button" phx-click="close_google_sso_modal">Cancel</.secondary_button>
          </.form_actions>
        </.form>
      </:body>
    </.app_modal>
    """
  end

  @impl true
  def handle_event("open_google_sso_modal", _params, %{assigns: %{can_manage: true, sso_info: info}} = socket)
      when not is_nil(info) do
    {:noreply,
     socket
     |> assign(:google_sso_form, google_sso_form(info))
     |> assign(:show_google_sso_modal, true)}
  end

  def handle_event("open_google_sso_modal", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Only organization admins can manage Google SSO settings.")}
  end

  def handle_event("close_google_sso_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_google_sso_modal, false)
     |> assign(:google_sso_form, google_sso_form(socket.assigns.sso_info))}
  end

  def handle_event("save_google_sso", %{"google_sso" => params}, %{assigns: assigns} = socket) do
    with true <- assigns.can_manage and not is_nil(assigns.sso_info),
         {:ok, parsed_params, validated_changeset} <-
           validate_google_sso_params(assigns.sso_info, params),
         {:ok, _provider} <- save_google_sso(assigns.organization, parsed_params, validated_changeset) do
      info = google_sso_info(assigns.organization)

      {:noreply,
       socket
       |> assign(:sso_info, info)
       |> assign(:show_google_sso_modal, false)
       |> assign(:google_sso_form, google_sso_form(info))
       |> put_flash(:info, "Google SSO settings updated")}
    else
      false ->
        {:noreply,
         socket
         |> put_flash(:error, "Only organization admins can manage Google SSO settings.")}

      {:error, %Changeset{} = changeset} ->
        {:noreply, assign(socket, :google_sso_form, to_form(changeset, as: :google_sso))}

      {:error, message} when is_binary(message) ->
        {:noreply, socket |> put_flash(:error, message)}
    end
  end

  defp load_sso_state(socket, membership) do
    organization =
      membership.organization || Organizations.get_organization!(membership.organization_id)

    info = google_sso_info(organization)

    socket
    |> assign(:current_membership, membership)
    |> assign(:organization, organization)
    |> assign(:can_manage, Organizations.membership_admin?(membership))
    |> assign(:sso_info, info)
    |> assign(:google_sso_form, google_sso_form(info))
  end

  defp google_sso_info(%{id: org_id} = organization) do
    config = google_oauth_config()
    client_id = config_value(config, :client_id)
    client_secret = config_value(config, :client_secret)
    credentials_present? = client_id && client_secret
    redirect_uri = config_value(config, :redirect_uri) || default_google_redirect_uri()

    provider = Organizations.get_sso_provider_for_org(organization, :google)

    domains =
      provider
      |> case do
        %{} = p -> Enum.map(p.domains || [], & &1.domain)
        _ -> []
      end

    %{
      organization_id: org_id,
      credentials_present?: !!credentials_present?,
      configured?: credentials_present? && match?(%{enabled: true}, provider) && Enum.any?(domains),
      enabled: match?(%{enabled: true}, provider),
      auto_provision: match?(%{auto_provision_members: true}, provider),
      domains: domains,
      redirect_uri: redirect_uri,
      provider: provider
    }
  end

  defp google_sso_status(nil), do: :warning
  defp google_sso_status(%{configured?: true}), do: :ok
  defp google_sso_status(%{credentials_present?: false}), do: :error
  defp google_sso_status(%{domains: []}), do: :warning
  defp google_sso_status(_info), do: :warning

  defp google_sso_form(nil), do: nil

  defp google_sso_form(info) do
    info
    |> google_sso_changeset(%{})
    |> to_form(as: :google_sso)
  end

  defp validate_google_sso_params(info, params) do
    changeset =
      info
      |> google_sso_changeset(params)
      |> Map.put(:action, :validate)

    case Changeset.apply_action(changeset, :update) do
      {:ok, data} ->
        domains = parse_domain_input(data.domains)

        attrs = %{
          "enabled" => data.enabled,
          "auto_provision_members" => if(data.enabled, do: data.auto_provision_members, else: false),
          "domains" => domains
        }

        {:ok, attrs, changeset}

      {:error, %Changeset{} = invalid_changeset} ->
        {:error, invalid_changeset}
    end
  end

  defp save_google_sso(organization, params, base_changeset) do
    case Organizations.upsert_google_sso_provider(organization, params) do
      {:ok, provider} ->
        {:ok, provider}

      {:error, {:changeset, %Changeset{} = changeset}} ->
        message = changeset_error(changeset)
        {:error, Changeset.add_error(base_changeset, :domains, message)}

      {:error, reason} ->
        {:error, format_reason(reason)}
    end
  end

  defp google_sso_changeset(info, params) do
    data = %{
      enabled: info.enabled || false,
      auto_provision_members: info.auto_provision || false,
      domains: info.domains |> Enum.join("\n")
    }

    types = %{enabled: :boolean, auto_provision_members: :boolean, domains: :string}

    {data, types}
    |> Changeset.cast(params, Map.keys(types))
    |> Changeset.validate_required([:enabled, :auto_provision_members])
    |> Changeset.update_change(:domains, &(&1 || ""))
    |> validate_domains()
  end

  defp validate_domains(%Changeset{} = changeset) do
    input = Changeset.get_field(changeset, :domains) || ""
    domains = parse_domain_input(input)

    changeset =
      if Changeset.get_field(changeset, :enabled) && Enum.empty?(domains) do
        Changeset.add_error(changeset, :domains, "add at least one domain when Google SSO is enabled")
      else
        changeset
      end

    {changeset, domains}
    |> ensure_domain_uniqueness()
    |> ensure_domain_format()
    |> elem(0)
  end

  defp ensure_domain_uniqueness({changeset, domains}) do
    duplicates = domains -- Enum.uniq(domains)

    updated_changeset =
      duplicates
      |> Enum.uniq()
      |> Enum.reduce(changeset, fn dup, acc ->
        Changeset.add_error(acc, :domains, "#{dup} is listed more than once")
      end)

    {updated_changeset, domains}
  end

  defp ensure_domain_format({changeset, domains}) do
    invalid = Enum.reject(domains, &valid_domain?/1)

    updated_changeset =
      Enum.reduce(invalid, changeset, fn domain, acc ->
        Changeset.add_error(acc, :domains, "#{domain} is not a valid domain")
      end)

    {updated_changeset, domains}
  end

  defp parse_domain_input(value) when is_binary(value) do
    value
    |> String.split(~r/[\s,]+/, trim: true)
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_domain_input(_), do: []

  defp valid_domain?(domain) do
    String.match?(domain, ~r/^[a-z0-9][a-z0-9.-]+\.[a-z]{2,}$/)
  end

  defp default_google_redirect_uri do
    TrifleWeb.Endpoint.url() <> "/auth/google/callback"
  rescue
    _ -> "/auth/google/callback"
  end

  defp google_oauth_config do
    base = normalize_config(Application.get_env(:trifle, :google_oauth, %{}))

    env_overrides =
      %{
        client_id:
          System.get_env("GOOGLE_OAUTH_CLIENT_ID") || System.get_env("GOOGLE_CLIENT_ID"),
        client_secret:
          System.get_env("GOOGLE_OAUTH_CLIENT_SECRET") || System.get_env("GOOGLE_CLIENT_SECRET"),
        redirect_uri:
          System.get_env("GOOGLE_OAUTH_REDIRECT_URI") || System.get_env("GOOGLE_REDIRECT_URI")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or String.trim(v) == "" end)
      |> Map.new()

    Map.merge(base, env_overrides, fn _key, _base, override -> override end)
  end

  defp normalize_config(config) when is_map(config), do: config
  defp normalize_config(config) when is_list(config), do: Map.new(config)
  defp normalize_config(_), do: %{}

  defp config_value(config, key) when is_map(config) do
    Map.get(config, key) || Map.get(config, Atom.to_string(key))
  end

  defp config_value(_config, _key), do: nil

  defp changeset_error(changeset) do
    changeset
    |> Changeset.traverse_errors(fn {msg, opts} ->
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
end
