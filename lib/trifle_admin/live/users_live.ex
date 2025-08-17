defmodule TrifleAdmin.UsersLive do
  use TrifleAdmin, :live_view

  alias Trifle.Accounts

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "User Management", users: list_users())}
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-base font-semibold leading-6 text-gray-900">Users</h1>
          <p class="mt-2 text-sm text-gray-700">
            A list of all users in the system including their email and admin status.
          </p>
        </div>
      </div>
      <div class="mt-8 flow-root">
        <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
          <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
            <table class="min-w-full divide-y divide-gray-300">
              <thead>
                <tr>
                  <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-0">
                    Email
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Admin
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Confirmed
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Created
                  </th>
                  <th scope="col" class="relative py-3.5 pl-3 pr-4 sm:pr-0">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for user <- @users do %>
                  <tr>
                    <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium text-gray-900 sm:pl-0">
                      <%= user.email %>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <%= if user.is_admin do %>
                        <span class="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20">Admin</span>
                      <% else %>
                        <span class="inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10">User</span>
                      <% end %>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <%= if user.confirmed_at do %>
                        <span class="text-green-600">Yes</span>
                      <% else %>
                        <span class="text-red-600">No</span>
                      <% end %>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <%= Calendar.strftime(user.inserted_at, "%Y-%m-%d") %>
                    </td>
                    <td class="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium sm:pr-0">
                      <%= if user.is_admin do %>
                        <button phx-click="revoke_admin" phx-value-id={user.id} 
                                class="text-red-600 hover:text-red-900">
                          Revoke Admin
                        </button>
                      <% else %>
                        <button phx-click="grant_admin" phx-value-id={user.id}
                                class="text-indigo-600 hover:text-indigo-900">
                          Grant Admin
                        </button>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
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