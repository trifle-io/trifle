defmodule TrifleAdmin.UsersLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Trifle.Accounts
  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.OrganizationMembership
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Users",
       user: nil,
       users: [],
       query: "",
       memberships_by_user_id: %{},
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])

    socket =
      socket
      |> assign_users(query, page)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply, push_patch(socket, to: ~p"/admin/users?#{Pagination.list_params(query, 1)}")}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  def handle_event("grant_admin", %{"id" => id}, socket) do
    case Accounts.update_user_admin_status(id, true) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign_users(socket.assigns.query, socket.assigns.pagination.page)
         |> put_flash(:info, "Admin access granted successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to grant admin access")}
    end
  end

  def handle_event("revoke_admin", %{"id" => id}, socket) do
    case Accounts.update_user_admin_status(id, false) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign_users(socket.assigns.query, socket.assigns.pagination.page)
         |> put_flash(:info, "Admin access revoked successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke admin access")}
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    user = Accounts.get_user!(id)
    memberships_by_user_id = ensure_memberships_for_user(socket, user.id)

    assign(socket, user: user, memberships_by_user_id: memberships_by_user_id)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, user: nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Users"
          description="A list of all users in the system including their email, organization, and admin status."
        >
          <:actions>
            <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
              <input
                type="search"
                name="q"
                value={@query}
                placeholder="Search users..."
                phx-debounce="300"
                autocomplete="off"
                class="block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
              />
            </.form>
          </:actions>
        </.admin_table_header>
      </:header>

      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Email</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
              <.admin_table_column>Admin</.admin_table_column>
              <.admin_table_column>Confirmed</.admin_table_column>
              <.admin_table_column>Created</.admin_table_column>
              <.admin_table_column actions />
            </:columns>

            <:rows>
              <%= for user <- @users do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/users/#{user}/show?#{Pagination.list_params(@query, @pagination.page)}"
                      }
                      class="group flex items-center space-x-3 text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400 transition-all duration-200 cursor-pointer"
                    >
                      <div class="flex-shrink-0">
                        <div class="w-10 h-10 bg-gradient-to-br from-teal-50 to-blue-50 dark:from-teal-900 dark:to-blue-900 rounded-lg flex items-center justify-center group-hover:from-teal-100 group-hover:to-blue-100 dark:group-hover:from-teal-800 dark:group-hover:to-blue-800 transition-all duration-200">
                          <svg
                            class="w-5 h-5 text-teal-600 dark:text-teal-400"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white transition-colors duration-200">
                          {user.email}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 transition-colors duration-200">
                          {if user.is_admin, do: "Administrator", else: "Standard User"}
                        </p>
                      </div>
                      <div class="flex-shrink-0">
                        <svg
                          class="w-4 h-4 text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9 5l7 7-7 7"
                          />
                        </svg>
                      </div>
                    </.link>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-gray-900 dark:text-white">
                        {organization_name(user, @memberships_by_user_id) || "N/A"}
                      </div>
                      <div class="text-xs text-gray-400 dark:text-gray-500">
                        {organization_role(user, @memberships_by_user_id) || "N/A"}
                      </div>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <%= if user.is_admin do %>
                      <.status_badge variant="admin">Admin</.status_badge>
                    <% else %>
                      <.status_badge>User</.status_badge>
                    <% end %>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="mb-1">
                        <%= if user.confirmed_at do %>
                          <.status_badge variant="success">Confirmed</.status_badge>
                        <% else %>
                          <.status_badge variant="warning">Unconfirmed</.status_badge>
                        <% end %>
                      </div>
                      <%= if user.confirmed_at do %>
                        <div class="text-xs text-gray-400 dark:text-gray-500">
                          {Calendar.strftime(user.confirmed_at, "%Y-%m-%d %H:%M")} UTC
                        </div>
                      <% else %>
                        <div class="text-xs text-gray-400 dark:text-gray-500">
                          Awaiting confirmation
                        </div>
                      <% end %>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-gray-900 dark:text-white">
                        {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
                      </div>
                      <div class="text-xs text-gray-400 dark:text-gray-500">
                        {Calendar.strftime(user.inserted_at, "%H:%M")} UTC
                      </div>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell actions>
                    <%= if user.is_admin do %>
                      <.table_action_button
                        variant="danger"
                        phx_click="revoke_admin"
                        phx_value_id={user.id}
                      >
                        Revoke Admin
                      </.table_action_button>
                    <% else %>
                      <.table_action_button
                        variant="primary"
                        phx_click="grant_admin"
                        phx_value_id={user.id}
                      >
                        Grant Admin
                      </.table_action_button>
                    <% end %>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/users"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="user-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/users?#{Pagination.list_params(@query, @pagination.page)}")}
    >
      <:title>User Details</:title>
      <:body>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Email</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@user.email}
              </dd>
            </div>
            <%= if @user.name do %>
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt class="text-sm font-medium text-gray-900 dark:text-white">Name</dt>
                <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                  {@user.name}
                </dd>
              </div>
            <% end %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {organization_name(@user, @memberships_by_user_id) || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Role</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {organization_role(@user, @memberships_by_user_id) || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Admin</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {if(@user.is_admin, do: "Yes", else: "No")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Confirmed</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                <%= if @user.confirmed_at do %>
                  {Calendar.strftime(@user.confirmed_at, "%B %d, %Y at %I:%M %p UTC")}
                <% else %>
                  Unconfirmed
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">User ID</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                {@user.id}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Created</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@user.inserted_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Updated</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@user.updated_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
          </dl>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp list_users(query, page) do
    base_query =
      from(u in User,
        left_join: m in OrganizationMembership,
        on: m.user_id == u.id,
        left_join: o in Organization,
        on: o.id == m.organization_id,
        order_by: [asc: u.email, asc: u.id],
        distinct: u.id,
        select: u
      )

    base_query
    |> filter_users(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp assign_users(socket, query, page) do
    {users, pagination} = list_users(query, page)
    memberships_by_user_id = memberships_by_user_id(users)

    assign(socket,
      users: users,
      pagination: pagination,
      query: query,
      memberships_by_user_id: memberships_by_user_id
    )
  end

  defp memberships_by_user_id(users) do
    user_ids =
      users
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    Organizations.list_memberships_for_users(user_ids)
    |> Map.new(&{&1.user_id, &1})
  end

  defp organization_name(user, memberships_by_user_id) do
    case Map.get(memberships_by_user_id, user.id) do
      %{organization: organization} -> organization.name
      _ -> nil
    end
  end

  defp organization_role(user, memberships_by_user_id) do
    case Map.get(memberships_by_user_id, user.id) do
      %{role: role} when is_binary(role) -> String.capitalize(role)
      _ -> nil
    end
  end

  defp filter_users(query, ""), do: query

  defp filter_users(query, term) do
    like = "%#{term}%"

    from([u, m, o] in query,
      where:
        ilike(u.email, ^like) or
          ilike(u.name, ^like) or
          ilike(fragment("CAST(? AS text)", u.id), ^like) or
          ilike(o.name, ^like) or
          ilike(o.slug, ^like) or
          ilike(m.role, ^like) or
          ilike(
            fragment(
              "CASE WHEN ? THEN 'system admin' ELSE 'standard user' END",
              u.is_admin
            ),
            ^like
          ) or
          ilike(fragment("CASE WHEN ? THEN 'admin' ELSE 'user' END", u.is_admin), ^like)
    )
  end

  defp ensure_memberships_for_user(socket, user_id) do
    if Map.has_key?(socket.assigns.memberships_by_user_id, user_id) do
      socket.assigns.memberships_by_user_id
    else
      Organizations.list_memberships_for_users([user_id])
      |> Map.new(&{&1.user_id, &1})
      |> Map.merge(socket.assigns.memberships_by_user_id)
    end
  end
end
