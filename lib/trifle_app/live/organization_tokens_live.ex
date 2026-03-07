defmodule TrifleApp.OrganizationTokensLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationApiToken
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.Source
  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Tokens")
      |> assign(:active_tab, :tokens)
      |> assign(:show_create_modal, false)
      |> assign(:show_edit_modal, false)
      |> assign(:issued_token, nil)
      |> assign(:token_error, nil)
      |> assign(:new_token_name, "")
      |> assign(:new_wildcard_read, false)
      |> assign(:new_wildcard_write, false)
      |> assign(:new_grants, %{})
      |> assign(:edit_token, nil)
      |> assign(:edit_error, nil)
      |> assign(:edit_wildcard_read, false)
      |> assign(:edit_wildcard_write, false)
      |> assign(:edit_grants, %{})
      |> assign(:edit_unknown_source_permissions, %{})

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization/profile")}

      true ->
        {:ok, load_state(socket, membership)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <%= if @current_membership do %>
        <Navigation.nav active_tab={@active_tab} />

        <div class="sm:flex sm:items-center">
          <div class="sm:flex-auto">
            <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
              Organization Tokens
            </h1>
            <p class="mt-2 text-sm text-gray-500 dark:text-slate-400">
              Shared API tokens controlling access to individual sources.
            </p>
          </div>
          <%= if @can_manage do %>
            <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
              <.primary_button type="button" phx-click="open_create_modal" class="gap-2">
                <span>New token</span>
              </.primary_button>
            </div>
          <% end %>
        </div>

        <div class="mt-6 overflow-hidden rounded-lg bg-white shadow-sm dark:bg-slate-800">
          <div class="border-b border-gray-100 dark:border-slate-700 px-4 py-3 text-sm font-semibold text-gray-900 dark:text-white">
            Tokens ({length(@tokens)})
          </div>

          <%= if Enum.empty?(@tokens) do %>
            <div class="px-6 py-12 text-center text-sm text-gray-500 dark:text-slate-400">
              No organization tokens yet.
            </div>
          <% else %>
            <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-700">
              <%= for token <- @tokens do %>
                <li class="px-4 py-4 sm:px-6">
                  <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <div>
                      <p class="text-sm font-medium text-gray-900 dark:text-white">
                        {token_display_name(token)}
                      </p>
                      <%= if wildcard_enabled?(token) do %>
                        <div class="mt-1 flex items-center gap-1.5 text-xs text-gray-500 dark:text-slate-400">
                          <span>Everything</span>
                          <span class="font-mono text-[10px] text-gray-500 dark:text-slate-400">
                            [{wildcard_permission_label(token)}]
                          </span>
                        </div>
                      <% end %>
                      <% grants = source_grants(token, @sources) %>
                      <div class="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-gray-500 dark:text-slate-400">
                        <span>Source grants:</span>
                        <%= if Enum.empty?(grants) do %>
                          <span>none</span>
                        <% else %>
                          <%= for grant <- grants do %>
                            <span class="inline-flex items-center gap-1 rounded-full border border-gray-200 px-2 py-0.5 text-gray-700 dark:border-slate-700 dark:text-slate-200">
                              <.source_type_icon
                                type={grant.type}
                                class="h-3.5 w-3.5 shrink-0 text-gray-500 dark:text-slate-300"
                              />
                              <span>{grant.name}</span>
                              <span class="font-mono text-[10px] text-gray-500 dark:text-slate-400">
                                [{grant.permission}]
                              </span>
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                        Last used: {format_datetime(token.last_used_at)} · Created: {format_datetime(
                          token.inserted_at
                        )}
                      </p>
                    </div>

                    <%= if @can_manage do %>
                      <div class="inline-flex items-center gap-2">
                        <button
                          type="button"
                          phx-click="open_edit_modal"
                          phx-value-id={token.id}
                          class="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white px-3 py-2 text-xs font-medium text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
                        >
                          Edit grants
                        </button>
                        <button
                          type="button"
                          phx-click="delete_token"
                          phx-value-id={token.id}
                          data-confirm="Are you sure?"
                          class="inline-flex items-center justify-center rounded-md border border-red-200 bg-white px-3 py-2 text-xs font-medium text-red-600 hover:bg-red-50 dark:border-red-400 dark:bg-slate-800 dark:text-red-300 dark:hover:bg-red-500/10"
                        >
                          Delete
                        </button>
                      </div>
                    <% end %>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <.app_modal
          id="organization-token-modal"
          show={@show_create_modal}
          on_cancel={JS.push("close_create_modal")}
          size="lg"
        >
          <:title>
            <%= if @issued_token do %>
              Token created
            <% else %>
              Create token
            <% end %>
          </:title>
          <:body>
            <%= if @issued_token do %>
              <div class="space-y-4">
                <p class="text-sm text-gray-600 dark:text-slate-300">
                  Copy the token now. You will not be able to see it again.
                </p>
                <code
                  id="organization_token_value"
                  class="block max-w-full break-all rounded-md bg-red-100 px-3 py-2 font-mono text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200"
                >
                  {@issued_token}
                </code>
                <div class="flex justify-end gap-2">
                  <button
                    type="button"
                    phx-click={JS.dispatch("phx:copy", to: "#organization_token_value")}
                    class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200"
                  >
                    Copy
                  </button>
                  <button
                    type="button"
                    phx-click="close_create_modal"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white hover:bg-teal-500"
                  >
                    Done
                  </button>
                </div>
              </div>
            <% else %>
              <form phx-submit="create_token" phx-change="change_token_form" class="space-y-4">
                <%= if @token_error do %>
                  <div class="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-500/10 dark:text-red-200">
                    {@token_error}
                  </div>
                <% end %>

                <label class="block text-sm">
                  <span class="text-gray-700 dark:text-slate-200">Name</span>
                  <input
                    type="text"
                    name="token[name]"
                    value={@new_token_name}
                    placeholder="CLI token"
                    class="mt-1 block w-full rounded-md border border-gray-300 bg-white px-2.5 py-2 text-sm text-gray-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
                  />
                </label>

                <div class="overflow-hidden rounded-md border border-gray-200 dark:border-slate-700">
                  <table class="min-w-full divide-y divide-gray-200 dark:divide-slate-700">
                    <thead class="bg-gray-50 dark:bg-slate-900/50">
                      <tr>
                        <th class="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-slate-300">
                          Grant
                        </th>
                        <th class="px-3 py-2 text-center text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-slate-300">
                          Read
                        </th>
                        <th class="px-3 py-2 text-center text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-slate-300">
                          Write
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100 dark:divide-slate-700">
                      <tr class="bg-gray-50/60 dark:bg-slate-900/40">
                        <td class="px-3 py-2 text-sm font-medium text-gray-900 dark:text-white">
                          Everything
                        </td>
                        <td class="px-3 py-2 text-center">
                          <input
                            type="checkbox"
                            name="token[wildcard_read]"
                            value="true"
                            checked={@new_wildcard_read}
                          />
                        </td>
                        <td class="px-3 py-2 text-center">
                          <input
                            type="checkbox"
                            name="token[wildcard_write]"
                            value="true"
                            checked={@new_wildcard_write}
                          />
                        </td>
                      </tr>
                      <%= for source <- @sources do %>
                        <% source_id = source_identifier(source) %>
                        <%= if source_id do %>
                          <tr>
                            <td class="px-3 py-2 text-sm text-gray-700 dark:text-slate-200">
                              <span class="inline-flex items-center gap-2">
                                <.source_type_icon
                                  source={source}
                                  class="h-4 w-4 shrink-0 text-gray-500 dark:text-slate-300"
                                />
                                <span>{source_grant_name(source)}</span>
                              </span>
                            </td>
                            <td class="px-3 py-2 text-center">
                              <%= if @new_wildcard_read do %>
                                <input
                                  type="checkbox"
                                  checked
                                  disabled
                                  class="cursor-not-allowed opacity-60"
                                />
                              <% else %>
                                <input
                                  type="checkbox"
                                  name={"token[grants][#{source_id}][read]"}
                                  value="true"
                                  checked={grant_checked?(@new_grants, source_id, :read)}
                                />
                              <% end %>
                            </td>
                            <td class="px-3 py-2 text-center">
                              <%= if not source_supports_write?(source) do %>
                                <input type="checkbox" disabled class="cursor-not-allowed opacity-60" />
                              <% else %>
                                <%= if @new_wildcard_write do %>
                                  <input
                                    type="checkbox"
                                    checked
                                    disabled
                                    class="cursor-not-allowed opacity-60"
                                  />
                                <% else %>
                                  <input
                                    type="checkbox"
                                    name={"token[grants][#{source_id}][write]"}
                                    value="true"
                                    checked={grant_checked?(@new_grants, source_id, :write)}
                                  />
                                <% end %>
                              <% end %>
                            </td>
                          </tr>
                        <% end %>
                      <% end %>
                    </tbody>
                  </table>
                </div>

                <div class="flex justify-end gap-2 pt-2">
                  <button
                    type="button"
                    phx-click="close_create_modal"
                    class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white hover:bg-teal-500"
                  >
                    Create
                  </button>
                </div>
              </form>
            <% end %>
          </:body>
        </.app_modal>

        <.app_modal
          id="organization-token-edit-modal"
          show={@show_edit_modal}
          on_cancel={JS.push("close_edit_modal")}
          size="lg"
        >
          <:title>Edit token grants</:title>
          <:body>
            <%= if @edit_token do %>
              <form
                phx-submit="update_token_grants"
                phx-change="change_edit_token_form"
                class="space-y-4"
              >
                <%= if @edit_error do %>
                  <div class="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-500/10 dark:text-red-200">
                    {@edit_error}
                  </div>
                <% end %>

                <div class="rounded-md border border-gray-200 bg-gray-50 px-3 py-2 dark:border-slate-700 dark:bg-slate-900/40">
                  <p class="text-xs uppercase tracking-wide text-gray-500 dark:text-slate-400">
                    Token
                  </p>
                  <p class="text-sm font-medium text-gray-900 dark:text-white">
                    {token_display_name(@edit_token)}
                  </p>
                </div>

                <div class="overflow-hidden rounded-md border border-gray-200 dark:border-slate-700">
                  <table class="min-w-full divide-y divide-gray-200 dark:divide-slate-700">
                    <thead class="bg-gray-50 dark:bg-slate-900/50">
                      <tr>
                        <th class="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-slate-300">
                          Grant
                        </th>
                        <th class="px-3 py-2 text-center text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-slate-300">
                          Read
                        </th>
                        <th class="px-3 py-2 text-center text-xs font-semibold uppercase tracking-wide text-gray-600 dark:text-slate-300">
                          Write
                        </th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-gray-100 dark:divide-slate-700">
                      <tr class="bg-gray-50/60 dark:bg-slate-900/40">
                        <td class="px-3 py-2 text-sm font-medium text-gray-900 dark:text-white">
                          Everything
                        </td>
                        <td class="px-3 py-2 text-center">
                          <input
                            type="checkbox"
                            name="token[wildcard_read]"
                            value="true"
                            checked={@edit_wildcard_read}
                          />
                        </td>
                        <td class="px-3 py-2 text-center">
                          <input
                            type="checkbox"
                            name="token[wildcard_write]"
                            value="true"
                            checked={@edit_wildcard_write}
                          />
                        </td>
                      </tr>
                      <%= for source <- @sources do %>
                        <% source_id = source_identifier(source) %>
                        <%= if source_id do %>
                          <tr>
                            <td class="px-3 py-2 text-sm text-gray-700 dark:text-slate-200">
                              <span class="inline-flex items-center gap-2">
                                <.source_type_icon
                                  source={source}
                                  class="h-4 w-4 shrink-0 text-gray-500 dark:text-slate-300"
                                />
                                <span>{source_grant_name(source)}</span>
                              </span>
                            </td>
                            <td class="px-3 py-2 text-center">
                              <%= if @edit_wildcard_read do %>
                                <input
                                  type="checkbox"
                                  checked
                                  disabled
                                  class="cursor-not-allowed opacity-60"
                                />
                              <% else %>
                                <input
                                  type="checkbox"
                                  name={"token[grants][#{source_id}][read]"}
                                  value="true"
                                  checked={grant_checked?(@edit_grants, source_id, :read)}
                                />
                              <% end %>
                            </td>
                            <td class="px-3 py-2 text-center">
                              <%= if not source_supports_write?(source) do %>
                                <input type="checkbox" disabled class="cursor-not-allowed opacity-60" />
                              <% else %>
                                <%= if @edit_wildcard_write do %>
                                  <input
                                    type="checkbox"
                                    checked
                                    disabled
                                    class="cursor-not-allowed opacity-60"
                                  />
                                <% else %>
                                  <input
                                    type="checkbox"
                                    name={"token[grants][#{source_id}][write]"}
                                    value="true"
                                    checked={grant_checked?(@edit_grants, source_id, :write)}
                                  />
                                <% end %>
                              <% end %>
                            </td>
                          </tr>
                        <% end %>
                      <% end %>
                    </tbody>
                  </table>
                </div>

                <div class="flex justify-end gap-2 pt-2">
                  <button
                    type="button"
                    phx-click="close_edit_modal"
                    class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white hover:bg-teal-500"
                  >
                    Save grants
                  </button>
                </div>
              </form>
            <% else %>
              <div class="text-sm text-gray-500 dark:text-slate-400">Token not found.</div>
            <% end %>
          </:body>
        </.app_modal>
      <% else %>
        <div class="rounded-md border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900 dark:border-blue-900/60 dark:bg-blue-500/10 dark:text-blue-100">
          Create an organization first to manage tokens.
        </div>
      <% end %>
    </div>
    """
  end

  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     socket
     |> reset_create_form()
     |> assign(:show_edit_modal, false)
     |> assign(:show_create_modal, true)
     |> assign(:issued_token, nil)
     |> assign(:token_error, nil)}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply,
     socket
     |> reset_create_form()
     |> assign(:show_create_modal, false)
     |> assign(:issued_token, nil)
     |> assign(:token_error, nil)}
  end

  def handle_event("open_edit_modal", %{"id" => id}, socket) do
    with %OrganizationMembership{} = membership <- socket.assigns.current_membership,
         true <- socket.assigns.can_manage,
         %OrganizationApiToken{} = token <- find_token(socket.assigns.tokens, id) do
      {:noreply,
       socket
       |> assign_edit_state_from_token(token)
       |> assign(:show_create_modal, false)
       |> assign(:show_edit_modal, true)
       |> assign(:edit_error, nil)
       |> refresh_tokens(membership.organization_id)}
    else
      nil ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      false ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Token could not be found.")}
    end
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> reset_edit_form()
     |> assign(:show_edit_modal, false)
     |> assign(:edit_error, nil)}
  end

  def handle_event("change_token_form", %{"token" => params}, socket) do
    {:noreply,
     socket
     |> assign_form_state(params)
     |> assign(:token_error, nil)}
  end

  def handle_event("change_edit_token_form", %{"token" => params}, socket) do
    {:noreply,
     socket
     |> assign_edit_form_state(params)
     |> assign(:edit_error, nil)}
  end

  def handle_event("create_token", %{"token" => params}, socket) do
    with %OrganizationMembership{} = membership <- socket.assigns.current_membership,
         true <- socket.assigns.can_manage,
         {:ok, attrs} <- token_create_attrs(socket, membership, params),
         {:ok, _record, value} <-
           Organizations.create_organization_api_token(socket.assigns.current_user, attrs) do
      {:noreply,
       socket
       |> assign(:issued_token, value)
       |> assign(:token_error, nil)
       |> refresh_tokens(membership.organization_id)}
    else
      nil ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      false ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      :error ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign_form_state(params)
         |> assign(:token_error, format_reason(reason))}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}
    end
  end

  def handle_event("update_token_grants", %{"token" => params}, socket) do
    with %OrganizationMembership{} = membership <- socket.assigns.current_membership,
         true <- socket.assigns.can_manage,
         {:ok, %OrganizationApiToken{} = token} <- ensure_edit_token(socket.assigns.edit_token),
         permissions <- token_permissions_from_form(socket.assigns.sources, params),
         permissions <-
           merge_unknown_source_permissions(
             permissions,
             socket.assigns.edit_unknown_source_permissions
           ),
         {:ok, _updated} <-
           Organizations.update_organization_api_token(token, %{permissions: permissions}) do
      {:noreply,
       socket
       |> reset_edit_form()
       |> assign(:show_edit_modal, false)
       |> assign(:edit_error, nil)
       |> refresh_tokens(membership.organization_id)
       |> put_flash(:info, "Token grants updated successfully.")}
    else
      nil ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      false ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      :not_found ->
        {:noreply, put_flash(socket, :error, "Token could not be found.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign_edit_form_state(params)
         |> assign(:edit_error, format_reason(reason))}
    end
  end

  def handle_event("delete_token", %{"id" => id}, socket) do
    with %OrganizationMembership{} = membership <- socket.assigns.current_membership,
         true <- socket.assigns.can_manage,
         %OrganizationApiToken{} = token <-
           Organizations.get_organization_api_token_for_org(membership.organization_id, id),
         {:ok, _deleted} <- Organizations.delete_organization_api_token(token) do
      {:noreply,
       socket
       |> refresh_tokens(membership.organization_id)
       |> put_flash(:info, "Token deleted successfully.")}
    else
      nil ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      false ->
        {:noreply,
         put_flash(socket, :error, "Only organization owners and admins can manage tokens.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Token could not be deleted.")}
    end
  end

  defp load_state(socket, %OrganizationMembership{} = membership) do
    can_manage =
      Organizations.membership_owner?(membership) or Organizations.membership_admin?(membership)

    socket
    |> assign(:current_membership, membership)
    |> assign(:can_manage, can_manage)
    |> assign(
      :tokens,
      Organizations.list_organization_api_tokens_for_org(membership.organization_id)
    )
    |> assign(:sources, Source.list_for_membership(membership))
  end

  defp refresh_tokens(socket, organization_id) do
    assign(socket, :tokens, Organizations.list_organization_api_tokens_for_org(organization_id))
  end

  defp find_token(tokens, id) when is_list(tokens) and is_binary(id) do
    Enum.find(tokens, &(&1.id == id))
  end

  defp find_token(_, _), do: nil

  defp ensure_edit_token(%OrganizationApiToken{} = token), do: {:ok, token}
  defp ensure_edit_token(_), do: :not_found

  defp token_create_attrs(socket, %OrganizationMembership{} = membership, params) do
    permissions = token_permissions_from_form(socket.assigns.sources, params)

    attrs = %{
      organization_id: membership.organization_id,
      permissions: permissions,
      created_by: "web-ui",
      created_from: socket_host(socket)
    }

    attrs =
      case normalize_name(params["name"]) do
        nil -> attrs
        name -> Map.put(attrs, :name, name)
      end

    {:ok, attrs}
  end

  defp token_permissions_from_form(sources, params) do
    wildcard_read = checkbox_enabled?(Map.get(params, "wildcard_read"))
    wildcard_write = checkbox_enabled?(Map.get(params, "wildcard_write"))
    grants = normalize_grants_form(Map.get(params, "grants", %{}))

    source_permissions =
      Enum.reduce(sources || [], %{}, fn source, acc ->
        source_id = source_identifier(source)
        source_type = source_type(source)
        grant = Map.get(grants, source_id || "", %{})
        read = not wildcard_read and checkbox_enabled?(Map.get(grant, "read"))

        write =
          not wildcard_write and source_supports_write?(source) and
            checkbox_enabled?(Map.get(grant, "write"))

        cond do
          is_nil(source_id) or is_nil(source_type) ->
            acc

          not (read or write) ->
            acc

          true ->
            case Organizations.source_key(source_type, source_id) do
              {:ok, key} ->
                Map.put(acc, key, %{"read" => read, "write" => write})

              _ ->
                acc
            end
        end
      end)

    Organizations.normalize_token_permissions(%{
      "wildcard" => %{"read" => wildcard_read, "write" => wildcard_write},
      "sources" => source_permissions
    })
  end

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_name(_), do: nil

  defp reset_create_form(socket) do
    socket
    |> assign(:new_token_name, "")
    |> assign(:new_wildcard_read, false)
    |> assign(:new_wildcard_write, false)
    |> assign(:new_grants, %{})
  end

  defp reset_edit_form(socket) do
    socket
    |> assign(:edit_token, nil)
    |> assign(:edit_wildcard_read, false)
    |> assign(:edit_wildcard_write, false)
    |> assign(:edit_grants, %{})
    |> assign(:edit_unknown_source_permissions, %{})
  end

  defp assign_edit_state_from_token(socket, %OrganizationApiToken{} = token) do
    permissions = Organizations.normalize_token_permissions(token.permissions)
    wildcard = Map.get(permissions, "wildcard", %{})
    source_permissions = Map.get(permissions, "sources", %{})
    sources = socket.assigns.sources || []

    socket
    |> assign(:edit_token, token)
    |> assign(:edit_wildcard_read, checkbox_enabled?(Map.get(wildcard, "read")))
    |> assign(:edit_wildcard_write, checkbox_enabled?(Map.get(wildcard, "write")))
    |> assign(:edit_grants, source_grants_for_form(source_permissions, sources))
    |> assign(
      :edit_unknown_source_permissions,
      unknown_source_permissions(source_permissions, sources)
    )
  end

  defp assign_edit_state_from_token(socket, _), do: socket

  defp assign_form_state(socket, params) when is_map(params) do
    socket
    |> assign(:new_token_name, form_name_value(params["name"]))
    |> assign(:new_wildcard_read, checkbox_enabled?(Map.get(params, "wildcard_read")))
    |> assign(:new_wildcard_write, checkbox_enabled?(Map.get(params, "wildcard_write")))
    |> assign(:new_grants, normalize_grants_form(Map.get(params, "grants", %{})))
  end

  defp assign_form_state(socket, _), do: socket

  defp assign_edit_form_state(socket, params) when is_map(params) do
    socket
    |> assign(:edit_wildcard_read, checkbox_enabled?(Map.get(params, "wildcard_read")))
    |> assign(:edit_wildcard_write, checkbox_enabled?(Map.get(params, "wildcard_write")))
    |> assign(:edit_grants, normalize_grants_form(Map.get(params, "grants", %{})))
  end

  defp assign_edit_form_state(socket, _), do: socket

  defp form_name_value(value) when is_binary(value), do: value
  defp form_name_value(_), do: ""

  defp normalize_grants_form(grants) when is_map(grants) do
    Enum.reduce(grants, %{}, fn {source_id, grant}, acc ->
      grant = if is_map(grant), do: grant, else: %{}
      source_id = normalize_name(source_id)
      read = checkbox_enabled?(Map.get(grant, "read") || Map.get(grant, :read))
      write = checkbox_enabled?(Map.get(grant, "write") || Map.get(grant, :write))

      if source_id && (read or write) do
        Map.put(acc, source_id, %{"read" => read, "write" => write})
      else
        acc
      end
    end)
  end

  defp normalize_grants_form(_), do: %{}

  defp source_grants_for_form(source_permissions, sources) when is_map(source_permissions) do
    Enum.reduce(sources || [], %{}, fn source, acc ->
      source_id = source_identifier(source)

      with source_id when is_binary(source_id) <- source_id,
           {:ok, source_key} <- source_key_for(source) do
        grant = Map.get(source_permissions, source_key, %{})
        read = checkbox_enabled?(Map.get(grant, "read") || Map.get(grant, :read))

        write =
          source_supports_write?(source) and
            checkbox_enabled?(Map.get(grant, "write") || Map.get(grant, :write))

        if read or write do
          Map.put(acc, source_id, %{"read" => read, "write" => write})
        else
          acc
        end
      else
        _ ->
          acc
      end
    end)
  end

  defp source_grants_for_form(_, _), do: %{}

  defp unknown_source_permissions(source_permissions, sources) when is_map(source_permissions) do
    known_keys =
      Enum.reduce(sources || [], MapSet.new(), fn source, acc ->
        case source_key_for(source) do
          {:ok, source_key} -> MapSet.put(acc, source_key)
          _ -> acc
        end
      end)

    source_permissions
    |> Enum.reject(fn {source_key, _grant} -> MapSet.member?(known_keys, source_key) end)
    |> Enum.into(%{})
  end

  defp unknown_source_permissions(_, _), do: %{}

  defp merge_unknown_source_permissions(permissions, unknown_source_permissions)
       when is_map(permissions) and is_map(unknown_source_permissions) do
    if map_size(unknown_source_permissions) == 0 do
      permissions
    else
      source_permissions =
        permissions
        |> Map.get("sources", %{})
        |> Map.merge(unknown_source_permissions)

      Map.put(permissions, "sources", source_permissions)
    end
  end

  defp merge_unknown_source_permissions(permissions, _), do: permissions

  defp grant_checked?(grants, source_id, permission)
       when is_map(grants) and is_binary(source_id) do
    grants
    |> Map.get(source_id, %{})
    |> Map.get(Atom.to_string(permission), false)
    |> checkbox_enabled?()
  end

  defp grant_checked?(_, _, _), do: false

  defp checkbox_enabled?(value) when value in [true, 1, "1", "true", "on"], do: true
  defp checkbox_enabled?(_), do: false

  defp source_identifier(%Source{record: %{id: id}}) when is_binary(id), do: id
  defp source_identifier(_), do: nil

  defp source_type(%Source{module: Trifle.Stats.Source.Database}), do: :database
  defp source_type(%Source{module: Trifle.Stats.Source.Project}), do: :project
  defp source_type(_), do: nil

  defp source_supports_write?(%Source{} = source) do
    source_type(source) == :project
  end

  defp source_supports_write?(_), do: false

  defp source_grant_name(%Source{} = source) do
    Source.display_name(source)
  end

  defp source_grant_name(_), do: "Unknown source"

  defp source_key_for(%Source{} = source) do
    with source_type when source_type in [:database, :project] <- source_type(source),
         source_id when is_binary(source_id) <- source_identifier(source),
         {:ok, key} <- Organizations.source_key(source_type, source_id) do
      {:ok, key}
    else
      _ -> :error
    end
  end

  defp source_key_for(_), do: :error

  defp source_type_icon(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "h-4 w-4 shrink-0 text-gray-500 dark:text-slate-300" end)
      |> assign(:resolved_type, resolve_icon_type(assigns))

    ~H"""
    <%= case @resolved_type do %>
      <% :database -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
          />
        </svg>
      <% :project -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
          />
        </svg>
      <% _ -> %>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={@class}
        >
          <circle cx="12" cy="12" r="9" />
        </svg>
    <% end %>
    """
  end

  defp resolve_icon_type(assigns) do
    cond do
      Map.has_key?(assigns, :type) ->
        normalize_source_type(assigns.type)

      match?(%Source{}, Map.get(assigns, :source)) ->
        source_type(assigns.source)

      true ->
        nil
    end
  end

  defp normalize_source_type(type) when type in [:database, :project], do: type
  defp normalize_source_type("database"), do: :database
  defp normalize_source_type("project"), do: :project
  defp normalize_source_type(_), do: nil

  defp wildcard_permission_label(%OrganizationApiToken{} = token) do
    permissions = Organizations.normalize_token_permissions(token.permissions)
    wildcard_grant = Map.get(permissions, "wildcard", %{})
    grant_permission_label(wildcard_grant)
  end

  defp wildcard_permission_label(_), do: "--"

  defp wildcard_enabled?(%OrganizationApiToken{} = token) do
    wildcard_permission_label(token) != "--"
  end

  defp wildcard_enabled?(_), do: false

  defp source_grants(%OrganizationApiToken{} = token, sources) do
    permissions = Organizations.normalize_token_permissions(token.permissions)
    source_grants = Map.get(permissions, "sources", %{})
    sources_by_key = source_key_meta_map(sources)

    source_grants
    |> Enum.map(fn {key, grant} ->
      source_meta = Map.get(sources_by_key, key, %{name: key, type: nil})

      %{
        key: key,
        name: source_meta.name,
        type: source_meta.type,
        permission: grant_permission_label(grant)
      }
    end)
    |> Enum.sort_by(fn grant -> String.downcase(grant.name) end)
  end

  defp source_grants(_, _), do: []

  defp source_key_meta_map(sources) when is_list(sources) do
    Enum.reduce(sources, %{}, fn source, acc ->
      case source_key_for(source) do
        {:ok, key} ->
          Map.put(acc, key, %{name: source_grant_name(source), type: source_type(source)})

        :error ->
          acc
      end
    end)
  end

  defp source_key_meta_map(_), do: %{}

  defp grant_permission_label(grant) when is_map(grant) do
    read = Map.get(grant, "read") == true or Map.get(grant, :read) == true
    write = Map.get(grant, "write") == true or Map.get(grant, :write) == true

    cond do
      read and write -> "RW"
      read -> "R"
      write -> "W"
      true -> "--"
    end
  end

  defp grant_permission_label(_), do: "--"

  defp token_display_name(%OrganizationApiToken{} = token) do
    name = normalize_name(token.name) || "Token"

    case token_last5(token) do
      nil -> name
      token_last5 -> "#{name} ending #{token_last5}"
    end
  end

  defp token_last5(%OrganizationApiToken{token_last5: token_last5}) when is_binary(token_last5) do
    case String.trim(token_last5) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp token_last5(_), do: nil

  defp format_datetime(nil), do: "never"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp format_datetime(_), do: "unknown"

  defp socket_host(socket) do
    case Map.get(socket, :host_uri) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end

  defp format_reason(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {_field, errors} -> errors end)
    |> Enum.join(", ")
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
