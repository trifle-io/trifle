defmodule TrifleAdmin.MonitorsLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Trifle.Monitors
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.Project
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Monitors",
       monitors: [],
       monitor: nil,
       projects_by_id: %{},
       databases_by_id: %{},
       query: "",
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])

    socket =
      socket
      |> assign_monitors(query, page)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply, push_patch(socket, to: ~p"/admin/monitors?#{Pagination.list_params(query, 1)}")}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    monitor =
      Monitors.get_monitor!(id, preload: [:organization, :dashboard])

    {projects_by_id, databases_by_id} = ensure_source_names(socket, monitor)

    assign(socket,
      monitor: monitor,
      projects_by_id: projects_by_id,
      databases_by_id: databases_by_id
    )
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, monitor: nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Monitors"
          description="Review monitor configuration and status across organizations."
        >
          <:actions>
            <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
              <input
                type="search"
                name="q"
                value={@query}
                placeholder="Search monitors..."
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
              <.admin_table_column first>Monitor</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
              <.admin_table_column>Owner</.admin_table_column>
              <.admin_table_column>Type</.admin_table_column>
              <.admin_table_column>Status</.admin_table_column>
              <.admin_table_column>Source</.admin_table_column>
              <.admin_table_column>Created</.admin_table_column>
            </:columns>

            <:rows>
              <%= for monitor <- @monitors do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/monitors/#{monitor}/show?#{Pagination.list_params(@query, @pagination.page)}"
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
                              d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {monitor.name}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {monitor.description || "No description"}
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
                    {organization_name(monitor)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {owner_email(monitor)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {format_enum(monitor.type)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col gap-1">
                      <%= if monitor.status == :active do %>
                        <.status_badge variant="success">Active</.status_badge>
                      <% else %>
                        <.status_badge variant="warning">Paused</.status_badge>
                      <% end %>
                      <.status_badge variant={trigger_badge_variant(monitor.trigger_status)}>
                        {format_enum(monitor.trigger_status)}
                      </.status_badge>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {source_label(monitor, @projects_by_id, @databases_by_id)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-gray-900 dark:text-white">
                        {Calendar.strftime(monitor.inserted_at, "%Y-%m-%d")}
                      </div>
                      <div class="text-xs text-gray-400 dark:text-gray-500">
                        {Calendar.strftime(monitor.inserted_at, "%H:%M")} UTC
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
          path={~p"/admin/monitors"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="monitor-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/monitors?#{Pagination.list_params(@query, @pagination.page)}")}
      size="xl"
    >
      <:title>Monitor Details</:title>
      <:body>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Name</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.name}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Description</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.description || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {organization_name(@monitor)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Owner</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {owner_email(@monitor)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Type</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_enum(@monitor.type)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Status</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_enum(@monitor.status)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Trigger Status</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_enum(@monitor.trigger_status)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Locked</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {if(@monitor.locked, do: "Yes", else: "No")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Source</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {source_label(@monitor, @projects_by_id, @databases_by_id)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Source Type</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_enum(@monitor.source_type)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Source ID</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                {@monitor.source_id || "N/A"}
              </dd>
            </div>
            <%= if @monitor.dashboard do %>
              <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
                <dt class="text-sm font-medium text-gray-900 dark:text-white">Dashboard</dt>
                <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                  {@monitor.dashboard.name}
                </dd>
              </div>
            <% end %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Alert Metric Key</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.alert_metric_key || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Alert Metric Path</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.alert_metric_path || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Alert Timeframe</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.alert_timeframe || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Alert Granularity</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.alert_granularity || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Notify Every</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@monitor.alert_notify_every}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Target</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@monitor.target) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Segment Values</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@monitor.segment_values) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Report Settings</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@monitor.report_settings) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Delivery Channels</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@monitor.delivery_channels) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Delivery Media</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if json = format_json(@monitor.delivery_media) do %>
                  <pre class="rounded-md bg-slate-900/90 p-3 text-xs text-slate-100 whitespace-pre-wrap">{json}</pre>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Monitor ID</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                {@monitor.id}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Created</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@monitor.inserted_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Updated</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@monitor.updated_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
          </dl>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp list_monitors(query, page) do
    base_query =
      from(m in Monitor,
        join: o in assoc(m, :organization),
        join: u in assoc(m, :user),
        left_join: dsh in assoc(m, :dashboard),
        left_join: db in Database,
        on: m.source_type == ^:database and db.id == m.source_id,
        left_join: p in Project,
        on: m.source_type == ^:project and p.id == m.source_id,
        order_by: [asc: m.inserted_at, asc: m.id],
        distinct: m.id,
        preload: [organization: o, user: u, dashboard: dsh]
      )

    base_query
    |> filter_monitors(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp assign_monitors(socket, query, page) do
    {monitors, pagination} = list_monitors(query, page)
    {projects_by_id, databases_by_id} = source_maps_for(monitors)

    assign(socket,
      monitors: monitors,
      pagination: pagination,
      query: query,
      projects_by_id: projects_by_id,
      databases_by_id: databases_by_id
    )
  end

  defp source_maps_for(monitors) do
    project_ids =
      monitors
      |> Enum.filter(&(to_string(&1.source_type) == "project"))
      |> Enum.map(& &1.source_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    database_ids =
      monitors
      |> Enum.filter(&(to_string(&1.source_type) == "database"))
      |> Enum.map(& &1.source_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    projects_by_id =
      Organizations.list_projects_by_ids(project_ids)
      |> Map.new(&{&1.id, &1})

    databases_by_id =
      Organizations.list_databases_by_ids(database_ids)
      |> Map.new(&{&1.id, &1})

    {projects_by_id, databases_by_id}
  end

  defp organization_name(%{organization: %{name: name}}), do: name
  defp organization_name(_), do: "N/A"

  defp owner_email(%{user: %{email: email}}), do: email
  defp owner_email(_), do: "N/A"

  defp source_label(monitor, projects_by_id, databases_by_id) do
    type = monitor.source_type |> to_string()

    case type do
      "database" ->
        name =
          case Map.get(databases_by_id, monitor.source_id) do
            %{display_name: display_name} -> display_name
            _ -> monitor.source_id || "N/A"
          end

        "Database: #{name}"

      "project" ->
        name =
          case Map.get(projects_by_id, monitor.source_id) do
            %{name: project_name} -> project_name
            _ -> monitor.source_id || "N/A"
          end

        "Project: #{name}"

      _ ->
        "#{String.capitalize(type)}: #{monitor.source_id || "N/A"}"
    end
  end

  defp format_enum(nil), do: "N/A"

  defp format_enum(value) when is_atom(value) do
    value |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
  end

  defp format_enum(value), do: to_string(value)

  defp trigger_badge_variant(:alerting), do: "error"
  defp trigger_badge_variant(:warning), do: "warning"
  defp trigger_badge_variant(:recovering), do: "warning"
  defp trigger_badge_variant(_), do: "default"

  defp filter_monitors(query, ""), do: query

  defp filter_monitors(query, term) do
    like = "%#{term}%"

    from([m, o, u, dsh, db, p] in query,
      where:
        ilike(m.name, ^like) or
          ilike(m.description, ^like) or
          ilike(o.name, ^like) or
          ilike(o.slug, ^like) or
          ilike(u.email, ^like) or
          ilike(u.name, ^like) or
          ilike(dsh.name, ^like) or
          ilike(db.display_name, ^like) or
          ilike(p.name, ^like) or
          ilike(fragment("CAST(? AS text)", m.source_id), ^like) or
          ilike(fragment("CAST(? AS text)", m.id), ^like) or
          ilike(fragment("CAST(? AS text)", m.type), ^like) or
          ilike(fragment("CAST(? AS text)", m.status), ^like) or
          ilike(fragment("CAST(? AS text)", m.trigger_status), ^like) or
          ilike(fragment("CAST(? AS text)", m.source_type), ^like)
    )
  end

  defp ensure_source_names(socket, monitor) do
    projects_by_id = socket.assigns.projects_by_id
    databases_by_id = socket.assigns.databases_by_id

    case to_string(monitor.source_type) do
      "project" ->
        if Map.has_key?(projects_by_id, monitor.source_id) do
          {projects_by_id, databases_by_id}
        else
          updated_projects =
            Organizations.list_projects_by_ids([monitor.source_id])
            |> Map.new(&{&1.id, &1})
            |> Map.merge(projects_by_id)

          {updated_projects, databases_by_id}
        end

      "database" ->
        if Map.has_key?(databases_by_id, monitor.source_id) do
          {projects_by_id, databases_by_id}
        else
          updated_databases =
            Organizations.list_databases_by_ids([monitor.source_id])
            |> Map.new(&{&1.id, &1})
            |> Map.merge(databases_by_id)

          {projects_by_id, updated_databases}
        end

      _ ->
        {projects_by_id, databases_by_id}
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
  defp normalize_json_value(%_{} = value), do: value |> Map.from_struct() |> normalize_json_value()

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
end
