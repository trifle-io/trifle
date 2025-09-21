defmodule TrifleAdmin.UsersLive do
  use TrifleAdmin, :live_view

  alias Trifle.Accounts

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "User Management", users: list_users())}
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Users"
          description="A list of all users in the system including their email and admin status."
        />
      </:header>

      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Email</.admin_table_column>
              <.admin_table_column>Admin</.admin_table_column>
              <.admin_table_column>Confirmed</.admin_table_column>
              <.admin_table_column>Created</.admin_table_column>
              <.admin_table_column actions />
            </:columns>

            <:rows>
              <%= for user <- @users do %>
                <tr>
                  <.admin_table_cell first>
                    <div class="group flex items-center space-x-3">
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
      </:body>
    </.admin_table>
    """
  end

  def handle_event("grant_admin", %{"id" => id}, socket) do
    case Accounts.update_user_admin_status(id, true) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(users: list_users())
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
         |> assign(users: list_users())
         |> put_flash(:info, "Admin access revoked successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to revoke admin access")}
    end
  end

  defp list_users do
    Accounts.list_users()
  end
end
