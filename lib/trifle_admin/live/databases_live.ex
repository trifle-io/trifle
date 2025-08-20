defmodule TrifleAdmin.DatabasesLive do
  use TrifleAdmin, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Database Management", databases: list_databases())}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Database")
    |> assign(:database, Organizations.get_database!(id))
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(:page_title, "Database Details")
    |> assign(:database, Organizations.get_database!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Database")
    |> assign(:database, %Database{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Database Management")
    |> assign(:database, nil)
  end

  def handle_info({TrifleAdmin.DatabasesLive.FormComponent, {:saved, _database}}, socket) do
    {:noreply, assign(socket, :databases, list_databases())}
  end

  def handle_info({:flash, type, message}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  def handle_info(:refresh_databases, socket) do
    {:noreply, assign(socket, :databases, list_databases())}
  end

  def handle_info(:refresh_and_close, socket) do
    {:noreply, 
     socket
     |> assign(:databases, list_databases())
     |> push_patch(to: ~p"/admin/databases")}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    {:ok, _} = Organizations.delete_database(database)

    {:noreply, assign(socket, databases: list_databases())}
  end

  def handle_event("setup", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    
    case Organizations.setup_database(database) do
      {:ok, message} ->
        # Also run a status check after successful setup to update the status
        {:ok, _updated_database, _setup_exists} = Organizations.check_database_status(database)
        {:noreply, socket |> put_flash(:info, message) |> assign(databases: list_databases())}
      {:error, error} ->
        {:noreply, socket |> put_flash(:error, "Setup failed: #{error}") |> assign(databases: list_databases())}
    end
  end

  def handle_event("nuke", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    
    case Organizations.nuke_database(database) do
      {:ok, message} ->
        {:noreply, socket |> put_flash(:info, message) |> assign(databases: list_databases())}
      {:error, error} ->
        {:noreply, put_flash(socket, :error, error)}
    end
  end

  def handle_event("check_status", %{"id" => id}, socket) do
    database = Organizations.get_database!(id)
    
    case Organizations.check_database_status(database) do
      {:ok, _updated_database, _setup_exists} ->
        {:noreply, socket |> put_flash(:info, "Status check completed successfully") |> assign(databases: list_databases())}
      {:error, _updated_database, error_msg} ->
        {:noreply, socket |> put_flash(:error, "Status check failed: #{error_msg}") |> assign(databases: list_databases())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="sm:flex sm:items-center">
        <div class="sm:flex-auto">
          <h1 class="text-base font-semibold leading-6 text-gray-900">Databases</h1>
          <p class="mt-2 text-sm text-gray-700">
            Manage database connections for Trifle::Stats drivers (Redis, PostgreSQL, MongoDB, SQLite).
          </p>
        </div>
        <div class="mt-4 sm:ml-16 sm:mt-0 sm:flex-none">
          <.link patch={~p"/admin/databases/new"} class="block rounded-md bg-indigo-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">
            Add Database
          </.link>
        </div>
      </div>
      <div class="mt-8 flow-root">
        <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
          <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
            <table class="min-w-full divide-y divide-gray-300">
              <thead>
                <tr>
                  <th scope="col" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 sm:pl-0">
                    Display Name
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Driver
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Host
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Port
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Identifier
                  </th>
                  <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">
                    Status
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-200">
                <%= for database <- @databases do %>
                  <tr>
                    <td class="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium sm:pl-0">
                      <.link patch={~p"/admin/databases/#{database}/show"} class="group flex items-center space-x-3 text-gray-900 hover:text-indigo-600 transition-all duration-200 cursor-pointer">
                        <div class="flex-shrink-0">
                          <div class="w-10 h-10 bg-gradient-to-br from-indigo-50 to-purple-50 rounded-lg flex items-center justify-center group-hover:from-indigo-100 group-hover:to-purple-100 transition-all duration-200">
                            <svg class="w-5 h-5 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
                            </svg>
                          </div>
                        </div>
                        <div class="flex-1 min-w-0">
                          <p class="text-sm font-semibold text-gray-900 group-hover:text-indigo-600 transition-colors duration-200">
                            <%= database.display_name %>
                          </p>
                          <p class="text-xs text-gray-500 group-hover:text-indigo-500 transition-colors duration-200">
                            Click to view details
                          </p>
                        </div>
                        <div class="flex-shrink-0">
                          <svg class="w-4 h-4 text-gray-400 group-hover:text-indigo-500 transition-colors duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                          </svg>
                        </div>
                      </.link>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <span class={driver_badge_class(database.driver)}>
                        <%= String.capitalize(database.driver) %>
                      </span>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <%= database.host || "N/A" %>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <%= database.port || "N/A" %>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <div class="flex flex-col">
                        <div class="text-xs text-gray-400 font-medium">
                          <%= cond do %>
                            <% database.driver == "sqlite" -> %>File Path
                            <% database.driver == "redis" -> %>Prefix
                            <% true -> %>Database
                          <% end %>
                        </div>
                        <div>
                          <%= cond do %>
                            <% database.driver == "sqlite" -> %>
                              <%= database.file_path || "N/A" %>
                            <% database.driver == "redis" -> %>
                              <%= get_in(database.config, ["prefix"]) || "trifle_stats" %>
                            <% true -> %>
                              <%= database.database_name || "N/A" %>
                          <% end %>
                        </div>
                      </div>
                    </td>
                    <td class="whitespace-nowrap px-3 py-4 text-sm text-gray-500">
                      <div class="flex flex-col">
                        <div class="mb-1">
                          <%= case database.last_check_status do %>
                            <% "success" -> %>
                              <span class="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/10">
                                Ready
                              </span>
                            <% "error" -> %>
                              <span class="inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/10">
                                Error
                              </span>
                            <% "pending" -> %>
                              <span class="inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-700 ring-1 ring-inset ring-yellow-600/10">
                                Pending
                              </span>
                            <% _ -> %>
                              <span class="inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-700 ring-1 ring-inset ring-gray-600/10">
                                Unknown
                              </span>
                          <% end %>
                        </div>
                        <%= if database.last_check_at do %>
                          <div class="text-xs text-gray-400">
                            <%= Calendar.strftime(database.last_check_at, "%Y-%m-%d %H:%M") %> UTC
                          </div>
                        <% end %>
                        <%= if database.last_error do %>
                          <div class="text-xs text-red-500 max-w-xs truncate" title={database.last_error}>
                            <%= database.last_error %>
                          </div>
                        <% end %>
                      </div>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>

    <.modal :if={@live_action in [:new, :edit]} id="database-modal" show on_cancel={JS.patch(~p"/admin/databases")}>
      <.live_component
        module={TrifleAdmin.DatabasesLive.FormComponent}
        id={@database.id || :new}
        title={@page_title}
        action={@live_action}
        database={@database}
        patch={~p"/admin/databases"}
      />
    </.modal>

    <.modal :if={@live_action == :show} id="database-details-modal" show on_cancel={JS.patch(~p"/admin/databases")}>
      <style>
        #database-details-modal-container {
          padding: 0 !important;
        }
      </style>
      <.live_component
        module={TrifleAdmin.DatabasesLive.DetailsComponent}
        id={@database.id}
        database={@database}
        patch={~p"/admin/databases"}
      />
    </.modal>
    """
  end

  defp list_databases do
    Organizations.list_databases()
  end

  defp driver_badge_class("redis"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class("postgres"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class("mongo"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class("sqlite"), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
  defp driver_badge_class(_), do: "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/10"
end