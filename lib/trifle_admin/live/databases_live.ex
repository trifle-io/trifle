defmodule TrifleAdmin.DatabasesLive do
  use TrifleAdmin, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  def mount(_params, _session, socket) do
    {:ok, assign(socket, 
      page_title: ["Admin", "Database Management"], 
      breadcrumb_links: [{"Admin", ~p"/admin"}, "Database Management"],
      databases: list_databases())}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    database = Organizations.get_database!(id)
    socket
    |> assign(:page_title, ["Admin", "Database Management", "Edit #{database.display_name}"])
    |> assign(:breadcrumb_links, [{"Admin", ~p"/admin"}, {"Database Management", ~p"/admin/databases"}, "Edit #{database.display_name}"])
    |> assign(:database, database)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    database = Organizations.get_database!(id)
    socket
    |> assign(:page_title, ["Admin", "Database Management", database.display_name])
    |> assign(:breadcrumb_links, [{"Admin", ~p"/admin"}, {"Database Management", ~p"/admin/databases"}, database.display_name])
    |> assign(:database, database)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, ["Admin", "Database Management", "New Database"])
    |> assign(:breadcrumb_links, [{"Admin", ~p"/admin"}, {"Database Management", ~p"/admin/databases"}, "New Database"])
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
    <.admin_table>
      <:header>
        <.admin_table_header 
          title="Databases" 
          description="Manage database connections for Trifle::Stats drivers (Redis, PostgreSQL, MongoDB, SQLite)."
        >
          <:actions>
            <.link patch={~p"/admin/databases/new"} class="inline-flex justify-center items-center rounded-lg bg-teal-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:focus:ring-offset-slate-800">
              Add Database
            </.link>
          </:actions>
        </.admin_table_header>
      </:header>
      
      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Display Name</.admin_table_column>
              <.admin_table_column>Driver</.admin_table_column>
              <.admin_table_column>Host</.admin_table_column>
              <.admin_table_column>Port</.admin_table_column>
              <.admin_table_column>Identifier</.admin_table_column>
              <.admin_table_column>Status</.admin_table_column>
            </:columns>
            
            <:rows>
              <%= for database <- @databases do %>
                <tr>
                  <.admin_table_cell first>
                    <.link patch={~p"/admin/databases/#{database}/show"} class="group flex items-center space-x-3 text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400 transition-all duration-200 cursor-pointer">
                      <div class="flex-shrink-0">
                        <div class="w-10 h-10 bg-gradient-to-br from-teal-50 to-blue-50 dark:from-teal-900 dark:to-blue-900 rounded-lg flex items-center justify-center group-hover:from-teal-100 group-hover:to-blue-100 dark:group-hover:from-teal-800 dark:group-hover:to-blue-800 transition-all duration-200">
                          <svg class="w-5 h-5 text-teal-600 dark:text-teal-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125" />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200">
                          <%= database.display_name %>
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200">
                          Click to view details
                        </p>
                      </div>
                      <div class="flex-shrink-0">
                        <svg class="w-4 h-4 text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                        </svg>
                      </div>
                    </.link>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <.database_label driver={database.driver} />
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <%= database.host || "N/A" %>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <%= database.port || "N/A" %>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-xs text-gray-400 dark:text-gray-500 font-medium">
                        <%= cond do %>
                          <% database.driver == "sqlite" -> %>File Path
                          <% database.driver == "redis" -> %>Prefix
                          <% true -> %>Database
                        <% end %>
                      </div>
                      <div class="text-gray-900 dark:text-white">
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
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="mb-1">
                        <%= case database.last_check_status do %>
                          <% "success" -> %>
                            <.status_badge variant="success">Ready</.status_badge>
                          <% "error" -> %>
                            <.status_badge variant="error">Error</.status_badge>
                          <% "pending" -> %>
                            <.status_badge variant="pending">Pending</.status_badge>
                          <% _ -> %>
                            <.status_badge>Unknown</.status_badge>
                        <% end %>
                      </div>
                      <%= if database.last_check_at do %>
                        <div class="text-xs text-gray-400 dark:text-gray-500">
                          <%= Calendar.strftime(database.last_check_at, "%Y-%m-%d %H:%M") %> UTC
                        </div>
                      <% end %>
                      <%= if database.last_error do %>
                        <div class="text-xs text-red-500 dark:text-red-400 max-w-xs truncate" title={database.last_error}>
                          <%= database.last_error %>
                        </div>
                      <% end %>
                    </div>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>
      </:body>
    </.admin_table>

    <.app_modal :if={@live_action in [:new, :edit]} id="database-modal" show on_cancel={JS.patch(~p"/admin/databases")}>
      <:title>{@page_title}</:title>
      <:body>
        <.live_component
          module={TrifleAdmin.DatabasesLive.FormComponent}
          id={@database.id || :new}
          title={@page_title}
          action={@live_action}
          database={@database}
          patch={~p"/admin/databases"}
        />
      </:body>
    </.app_modal>

    <.app_modal :if={@live_action == :show} id="database-details-modal" show on_cancel={JS.patch(~p"/admin/databases")}>
      <:title>Database Details</:title>
      <:body>
        <.live_component
          module={TrifleAdmin.DatabasesLive.DetailsComponent}
          id={@database.id}
          database={@database}
          patch={~p"/admin/databases"}
        />
      </:body>
    </.app_modal>
    """
  end

  defp list_databases do
    Organizations.list_databases()
  end

end