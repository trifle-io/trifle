defmodule TrifleAdmin.DashboardsLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.Dashboard
  alias Trifle.Organizations.Project
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboards",
       dashboards: [],
       dashboard: nil,
       projects_by_id: %{},
       query: "",
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])

    socket =
      socket
      |> assign_dashboards(query, page)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply, push_patch(socket, to: ~p"/admin/dashboards?#{Pagination.list_params(query, 1)}")}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    dashboard =
      id
      |> Organizations.get_dashboard!()
      |> Repo.preload(:organization)

    projects_by_id = ensure_project_names(socket, dashboard)

    assign(socket, dashboard: dashboard, projects_by_id: projects_by_id)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, dashboard: nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Dashboards"
          description="Explore dashboard configurations across the platform."
        >
          <:actions>
            <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
              <input
                type="search"
                name="q"
                value={@query}
                placeholder="Search dashboards..."
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
              <.admin_table_column first>Dashboard</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
              <.admin_table_column>Owner</.admin_table_column>
              <.admin_table_column>Source</.admin_table_column>
              <.admin_table_column>Visibility</.admin_table_column>
              <.admin_table_column>Created</.admin_table_column>
            </:columns>

            <:rows>
              <%= for dashboard <- @dashboards do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/dashboards/#{dashboard}/show?#{Pagination.list_params(@query, @pagination.page)}"
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
                              d="M4 6h16M4 12h16M4 18h16"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {dashboard.name}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200">
                          Key: {dashboard.key}
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
                    {organization_name(dashboard)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {owner_email(dashboard)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {source_label(dashboard, @projects_by_id)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col gap-1">
                      <%= if dashboard.visibility do %>
                        <.status_badge variant="success">Everyone</.status_badge>
                      <% else %>
                        <.status_badge>Personal</.status_badge>
                      <% end %>
                      <%= if dashboard.locked do %>
                        <.status_badge variant="warning">Locked</.status_badge>
                      <% end %>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-gray-900 dark:text-white">
                        {Calendar.strftime(dashboard.inserted_at, "%Y-%m-%d")}
                      </div>
                      <div class="text-xs text-gray-400 dark:text-gray-500">
                        {Calendar.strftime(dashboard.inserted_at, "%H:%M")} UTC
                      </div>
                    </div>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/dashboards"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="dashboard-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/dashboards?#{Pagination.list_params(@query, @pagination.page)}")}
      size="xl"
    >
      <:title>Dashboard Details</:title>
      <:body>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Name</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@dashboard.name}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {organization_name(@dashboard)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Owner</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {owner_email(@dashboard)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Visibility</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {if(@dashboard.visibility, do: "Everyone", else: "Personal")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Locked</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {if(@dashboard.locked, do: "Yes", else: "No")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Source</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {source_label(@dashboard, @projects_by_id)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Source Type</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_source_type(@dashboard.source_type)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Source ID</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                {@dashboard.source_id || "N/A"}
              </dd>
            </div>
            <%= if @dashboard.database do %>
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt class="text-sm font-medium text-gray-900 dark:text-white">Database</dt>
                <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                  {@dashboard.database.display_name}
                </dd>
              </div>
            <% end %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Key</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono">
                {@dashboard.key}
              </dd>
            </div>
            <%= if @dashboard.access_token do %>
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt class="text-sm font-medium text-gray-900 dark:text-white">Access Token</dt>
                <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                  {@dashboard.access_token}
                </dd>
              </div>
            <% end %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Default Timeframe</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@dashboard.default_timeframe || "Not set"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Default Granularity</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@dashboard.default_granularity || "Not set"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Payload</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@dashboard.payload) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Segments</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@dashboard.segments) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Dashboard ID</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                {@dashboard.id}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Created</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@dashboard.inserted_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Updated</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@dashboard.updated_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
          </dl>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp list_dashboards(query, page) do
    base_query =
      from(d in Dashboard,
        join: o in assoc(d, :organization),
        join: u in User,
        on: u.id == d.user_id,
        left_join: db in assoc(d, :database),
        left_join: p in Project,
        on: d.source_type == "project" and p.id == d.source_id,
        order_by: [asc: d.inserted_at, asc: d.id],
        distinct: d.id,
        preload: [organization: o, user: u, database: db]
      )

    base_query
    |> filter_dashboards(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp assign_dashboards(socket, query, page) do
    {dashboards, pagination} = list_dashboards(query, page)
    projects_by_id = projects_by_id_for(dashboards)

    assign(socket,
      dashboards: dashboards,
      pagination: pagination,
      query: query,
      projects_by_id: projects_by_id
    )
  end

  defp projects_by_id_for(dashboards) do
    project_ids =
      dashboards
      |> Enum.filter(&(to_string(&1.source_type) == "project"))
      |> Enum.map(& &1.source_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Organizations.list_projects_by_ids(project_ids)
    |> Map.new(&{&1.id, &1})
  end

  defp organization_name(%{organization: %{name: name}}), do: name
  defp organization_name(_), do: "N/A"

  defp owner_email(%{user: %{email: email}}), do: email
  defp owner_email(_), do: "N/A"

  defp source_label(dashboard, projects_by_id) do
    type = dashboard.source_type |> to_string()

    case type do
      "database" ->
        name =
          case dashboard.database do
            %{display_name: display_name} -> display_name
            _ -> dashboard.source_id || "N/A"
          end

        "Database: #{name}"

      "project" ->
        name =
          case Map.get(projects_by_id, dashboard.source_id) do
            %{name: project_name} -> project_name
            _ -> dashboard.source_id || "N/A"
          end

        "Project: #{name}"

      _ ->
        "#{String.capitalize(type)}: #{dashboard.source_id || "N/A"}"
    end
  end

  defp filter_dashboards(query, ""), do: query

  defp filter_dashboards(query, term) do
    like = "%#{term}%"

    from([d, o, u, db, p] in query,
      where:
        ilike(d.name, ^like) or
          ilike(d.key, ^like) or
          ilike(o.name, ^like) or
          ilike(o.slug, ^like) or
          ilike(u.email, ^like) or
          ilike(u.name, ^like) or
          ilike(db.display_name, ^like) or
          ilike(p.name, ^like) or
          ilike(d.source_type, ^like) or
          ilike(fragment("CAST(? AS text)", d.source_id), ^like) or
          ilike(fragment("CAST(? AS text)", d.id), ^like)
    )
  end

  defp ensure_project_names(socket, dashboard) do
    case to_string(dashboard.source_type) do
      "project" ->
        if Map.has_key?(socket.assigns.projects_by_id, dashboard.source_id) do
          socket.assigns.projects_by_id
        else
          Organizations.list_projects_by_ids([dashboard.source_id])
          |> Map.new(&{&1.id, &1})
          |> Map.merge(socket.assigns.projects_by_id)
        end

      _ ->
        socket.assigns.projects_by_id
    end
  end

  defp format_json(nil), do: nil

  defp format_json(value) do
    normalized = normalize_json_value(value)

    cond do
      normalized in [%{}, []] ->
        nil

      true ->
        case Jason.encode(normalized, pretty: true) do
          {:ok, json} -> json
          _ -> inspect(value, pretty: true)
        end
    end
  end

  defp normalize_json_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_json_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_json_value(value) when is_atom(value), do: Atom.to_string(value)

  defp normalize_json_value(%_{} = value),
    do: value |> Map.from_struct() |> normalize_json_value()

  defp normalize_json_value(value) when is_list(value) do
    Enum.map(value, &normalize_json_value/1)
  end

  defp normalize_json_value(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, val}, acc ->
      Map.put(acc, to_string(key), normalize_json_value(val))
    end)
  end

  defp normalize_json_value(value), do: value

  defp format_source_type(nil), do: "N/A"

  defp format_source_type(value) when is_binary(value) do
    String.capitalize(value)
  end

  defp format_source_type(value) do
    value |> to_string() |> String.capitalize()
  end
end
