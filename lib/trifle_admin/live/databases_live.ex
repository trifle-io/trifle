defmodule TrifleAdmin.DatabasesLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Databases",
       databases: [],
       database: nil,
       query: "",
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])
    {databases, pagination} = list_databases(query, page)

    socket =
      socket
      |> assign(databases: databases, pagination: pagination, query: query)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply, push_patch(socket, to: ~p"/admin/databases?#{Pagination.list_params(query, 1)}")}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    database =
      id
      |> Organizations.get_database!()
      |> Repo.preload(:organization)

    assign(socket, database: database)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, database: nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Databases"
          description="Browse configured database connections and status."
        >
          <:actions>
            <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
              <input
                type="search"
                name="q"
                value={@query}
                placeholder="Search databases..."
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
              <.admin_table_column first>Display Name</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
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
                    <.link
                      patch={
                        ~p"/admin/databases/#{database}/show?#{Pagination.list_params(@query, @pagination.page)}"
                      }
                      class="group flex items-center space-x-3 text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400 transition-all duration-200 cursor-pointer"
                    >
                      <div class="flex-shrink-0">
                        <div class="w-10 h-10 bg-gradient-to-br from-teal-50 to-blue-50 dark:from-teal-900 dark:to-blue-900 rounded-lg flex items-center justify-center group-hover:from-teal-100 group-hover:to-blue-100 dark:group-hover:from-teal-800 dark:group-hover:to-blue-800 transition-all duration-200">
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                            class="w-5 h-5 text-teal-600 dark:text-teal-400"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {database.display_name}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200">
                          Click to view details
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
                    {(database.organization && database.organization.name) || "N/A"}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <.database_label driver={database.driver} />
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {database.host || "N/A"}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {database.port || "N/A"}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-xs text-gray-400 dark:text-gray-500 font-medium">
                        <%= cond do %>
                          <% database.driver == "sqlite" -> %>
                            File Path
                          <% database.driver == "redis" -> %>
                            Prefix
                          <% true -> %>
                            Database
                        <% end %>
                      </div>
                      <div class="text-gray-900 dark:text-white">
                        <%= cond do %>
                          <% database.driver == "sqlite" -> %>
                            {database.file_path || "N/A"}
                          <% database.driver == "redis" -> %>
                            {get_in(database.config, ["prefix"]) || "trifle_stats"}
                          <% true -> %>
                            {database.database_name || "N/A"}
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
                          {Calendar.strftime(database.last_check_at, "%Y-%m-%d %H:%M")} UTC
                        </div>
                      <% end %>
                      <%= if database.last_error do %>
                        <div
                          class="text-xs text-red-500 dark:text-red-400 max-w-xs truncate"
                          title={database.last_error}
                        >
                          {database.last_error}
                        </div>
                      <% end %>
                    </div>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/databases"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="database-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/databases?#{Pagination.list_params(@query, @pagination.page)}")}
    >
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

  defp list_databases(query, page) do
    base_query =
      from(d in Database,
        left_join: o in assoc(d, :organization),
        preload: [organization: o],
        order_by: [asc: d.display_name, asc: d.id]
      )

    base_query
    |> filter_databases(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp filter_databases(query, ""), do: query

  defp filter_databases(query, term) do
    like = "%#{term}%"

    from([d, o] in query,
      where:
        ilike(d.display_name, ^like) or
          ilike(d.driver, ^like) or
          ilike(d.host, ^like) or
          ilike(d.database_name, ^like) or
          ilike(d.file_path, ^like) or
          ilike(fragment("CAST(? AS text)", d.port), ^like) or
          ilike(fragment("?->>'prefix'", d.config), ^like) or
          ilike(o.name, ^like) or
          ilike(o.slug, ^like) or
          ilike(fragment("CAST(? AS text)", d.id), ^like)
    )
  end
end
