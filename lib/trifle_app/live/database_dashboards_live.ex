defmodule TrifleApp.DatabaseDashboardsLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.{Database, Dashboard}

  def mount(%{"id" => database_id}, _session, socket) do
    database = Organizations.get_database!(database_id)

    {:ok,
     socket
     |> assign(:database, database)
     |> assign(:page_title, ["Database", database.display_name, "Dashboards"])
     |> assign(:breadcrumb_links, [
       {"Database", ~p"/app/dbs"},
       {database.display_name, ~p"/app/dbs/#{database_id}/dashboards"},
       "Dashboards"
     ])
     |> assign(:dashboards_count, Organizations.list_dashboards_for_database(database) |> length())
     |> assign(:groups_tree, Organizations.list_dashboard_tree_for_database(database))
     |> assign(:ungrouped_dashboards, Organizations.list_dashboards_for_group(database, nil))
     |> assign(:editing_group_id, nil)
     |> assign(:collapsed_groups, MapSet.new())}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:dashboard, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:dashboard, %Dashboard{})
  end

  def handle_info({TrifleApp.DatabaseDashboardsLive.FormComponent, {:saved, _dashboard}}, socket) do
    {:noreply, refresh_tree(socket)}
  end

  def handle_event("delete_dashboard", %{"id" => id}, socket) do
    dashboard = Organizations.get_dashboard!(id)
    {:ok, _} = Organizations.delete_dashboard(dashboard)

    {:noreply,
     socket
     |> refresh_tree()
     |> put_flash(:info, "Dashboard deleted successfully")}
  end

  def handle_event("dashboard_clicked", %{"id" => dashboard_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/dbs/#{socket.assigns.database.id}/dashboards/#{dashboard_id}")}
  end

  # No-op click handler to prevent bubbling to parent row toggle
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  # Group CRUD
  def handle_event("set_collapsed_groups", %{"ids" => ids}, socket) do
    ids = ids || []
    {:noreply, assign(socket, :collapsed_groups, MapSet.new(ids))}
  end

  def handle_event("toggle_group", %{"id" => id}, socket) do
    collapsed = socket.assigns.collapsed_groups || MapSet.new()
    collapsed = if MapSet.member?(collapsed, id), do: MapSet.delete(collapsed, id), else: MapSet.put(collapsed, id)
    socket = socket |> assign(:collapsed_groups, collapsed) |> push_event("save_collapsed_groups", %{ids: MapSet.to_list(collapsed)})
    {:noreply, socket}
  end

  def handle_event("expand_all_groups", _params, socket) do
    socket = socket |> assign(:collapsed_groups, MapSet.new()) |> push_event("save_collapsed_groups", %{ids: []})
    {:noreply, socket}
  end

  def handle_event("collapse_all_groups", _params, socket) do
    ids = socket.assigns.groups_tree |> all_group_ids()
    socket = socket |> assign(:collapsed_groups, MapSet.new(ids)) |> push_event("save_collapsed_groups", %{ids: ids})
    {:noreply, socket}
  end

  defp all_group_ids(tree) when is_list(tree) do
    Enum.flat_map(tree, &all_group_ids/1)
  end
  defp all_group_ids(%{group: group, children: children}) do
    [group.id | all_group_ids(children)]
  end

  def handle_event("start_rename_group", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_group_id, id)}
  end

  def handle_event("cancel_rename_group", _params, socket) do
    {:noreply, assign(socket, :editing_group_id, nil)}
  end

  def handle_event("new_group", params, socket) do
    name = Map.get(params, "name", "New Group")
    parent_id = Map.get(params, "parent_id")
    attrs = %{"name" => name, "database_id" => socket.assigns.database.id, "parent_group_id" => parent_id}
    case Organizations.create_dashboard_group(attrs) do
      {:ok, _group} -> {:noreply, refresh_tree(socket)}
      {:error, _cs} -> {:noreply, put_flash(socket, :error, "Could not create group")}
    end
  end

  def handle_event("rename_group", %{"id" => id, "name" => name}, socket) do
    group = Organizations.get_dashboard_group!(id)
    case Organizations.update_dashboard_group(group, %{name: name}) do
      {:ok, _} -> {:noreply, socket |> assign(:editing_group_id, nil) |> refresh_tree()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not rename group")}
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    group = Organizations.get_dashboard_group!(id)
    case Organizations.delete_dashboard_group(group) do
      {:ok, _} -> {:noreply, refresh_tree(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete group")}
    end
  end

  # Reorder events from Sortable (mixed groups + dashboards)
  def handle_event("reorder_nodes", %{"items" => items, "parent_id" => parent_id, "from_items" => from_items, "from_parent_id" => from_parent_id, "moved_id" => moved_id, "moved_type" => moved_type}, socket) do
    p = normalize_parent(parent_id)
    fp = normalize_parent(from_parent_id)
    case Organizations.reorder_nodes(socket.assigns.database, p, items, fp, from_items, moved_id, moved_type) do
      {:ok, _} -> {:noreply, refresh_tree(socket)}
      {:error, :invalid_parent} -> {:noreply, put_flash(socket, :error, "Cannot move a group under its descendant")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Failed to reorder")}
    end
  end

  defp normalize_parent(""), do: nil
  defp normalize_parent(nil), do: nil
  defp normalize_parent(id), do: id

  defp refresh_tree(socket) do
    database = socket.assigns.database
    socket
    |> assign(:dashboards_count, Organizations.list_dashboards_for_database(database) |> length())
    |> assign(:groups_tree, Organizations.list_dashboard_tree_for_database(database))
    |> assign(:ungrouped_dashboards, Organizations.list_dashboards_for_group(database, nil))
  end

  defp gravatar_url(email) do
    hash = email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
  end

  # Mixed nodes helpers
  defp mixed_root_nodes(groups_tree, ungrouped_dashboards) do
    groups = Enum.map(groups_tree, fn node -> {:group, node} end)
    dashes = Enum.map(ungrouped_dashboards, fn d -> {:dashboard, d} end)
    Enum.sort_by(groups ++ dashes, fn
      {:group, n} -> n.group.position || 0
      {:dashboard, d} -> d.position || 0
    end)
  end

  defp mixed_group_nodes(node) do
    groups = Enum.map(node.children, fn child -> {:group, child} end)
    dashes = Enum.map(node.dashboards, fn d -> {:dashboard, d} end)
    Enum.sort_by(groups ++ dashes, fn
      {:group, n} -> n.group.position || 0
      {:dashboard, d} -> d.position || 0
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col dark:bg-slate-900 min-h-screen">
      <!-- Tab Navigation -->
      <div class="mb-6 border-b border-gray-200 dark:border-slate-700">
        <nav class="-mb-px space-x-8" aria-label="Tabs">
          <.link
            navigate={~p"/app/dbs/#{@database.id}/dashboards"}
            class="border-teal-500 text-teal-600 dark:text-teal-400 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
            aria-current="page"
          >
            <svg
              class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
              />
            </svg>
            <span class="hidden sm:block">Dashboards</span>
          </.link>
          <.link
            navigate={~p"/app/dbs/#{@database.id}/transponders"}
            class="border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
          >
            <svg
              class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
              />
            </svg>
            <span class="hidden sm:block">Transponders</span>
          </.link>
          <.link
            navigate={~p"/app/dbs/#{@database.id}"}
            class="border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
          >
            <svg
              class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0112 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621.504 1.125 1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5"/>
            </svg>
            <span class="hidden sm:block">Explore</span>
          </.link>
          <.link
            navigate={~p"/app/dbs/#{@database.id}/settings"}
            class="float-right border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
          >
            <svg
              class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z"
              />
            </svg>
            <span class="hidden sm:block">Settings</span>
          </.link>
        </nav>
      </div>

      <!-- Dashboards Index -->
      <div class="mb-6">
        <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
          <div id="dashboards-header-controls" class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-3 border-b border-gray-100 dark:border-slate-700 flex items-center justify-between" phx-hook="FastTooltip">
            <div class="flex items-center gap-2">
              <span>Dashboards</span>
              <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30"><%= @dashboards_count %></span>
            </div>
            <div class="flex items-center gap-2">
              <.link
                patch={~p"/app/dbs/#{@database.id}/dashboards/new"}
                aria-label="New Dashboard"
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
              >
                <svg class="-ml-0.5 mr-1.5 h-5 w-5" viewBox="0 0 20 20" fill="currentColor"><path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" /></svg>
                <span class="hidden md:inline">New Dashboard</span>
              </.link>
              <button type="button" phx-click="new_group" aria-label="New Group" class="inline-flex items-center rounded-md bg-slate-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-slate-500">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="-ml-0.5 mr-1.5 h-5 w-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z" />
                </svg>
                <span class="hidden md:inline">New Group</span>
              </button>
              <button type="button" phx-click="expand_all_groups" data-tooltip="Expand All" class="inline-flex items-center rounded-md bg-white dark:bg-slate-800 border border-gray-300 dark:border-slate-600 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 9.776c.112-.017.227-.026.344-.026h15.812c.117 0 .232.009.344.026m-16.5 0a2.25 2.25 0 0 0-1.883 2.542l.857 6a2.25 2.25 0 0 0 2.227 1.932H19.05a2.25 2.25 0 0 0 2.227-1.932l.857-6a2.25 2.25 0 0 0-1.883-2.542m-16.5 0V6A2.25 2.25 0 0 1 6 3.75h3.879a1.5 1.5 0 0 1 1.06.44l2.122 2.12a1.5 1.5 0 0 0 1.06.44H18A2.25 2.25 0 0 1 20.25 9v.776" />
                </svg>
              </button>
              <button type="button" phx-click="collapse_all_groups" data-tooltip="Collapse All" class="inline-flex items-center rounded-md bg-white dark:bg-slate-800 border border-gray-300 dark:border-slate-600 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z" />
                </svg>
              </button>
            </div>
          </div>

          <div class="divide-y divide-gray-100 dark:divide-slate-700">
            <div class="p-2" id="dashboard-root" phx-hook="DashboardGroupsCollapse" data-db-id={@database.id}>
              <!-- Top-level Groups -->
              <div id="dashboard-root-groups" data-parent-id="" data-group="dashboard-nodes" data-event="reorder_nodes" data-handle=".drag-handle" phx-hook="Sortable" class="flex flex-col" style="min-height: 14px;">
                <%= for node <- @groups_tree do %>
                  <%= render_group(%{node: node, level: 0, database: @database, editing_group_id: @editing_group_id, collapsed_groups: @collapsed_groups}) %>
                <% end %>
              </div>

              <!-- Ungrouped Dashboards at bottom -->
              <div class="mt-6 pt-4 border-t border-gray-200 dark:border-slate-700">
                <div class="flex items-center gap-2 text-xs uppercase tracking-wide text-gray-500 dark:text-slate-400 px-2 mb-2" data-group-header="">
                  <span>Ungrouped</span>
                  <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-0.5 text-[10px] font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
                    <%= length(@ungrouped_dashboards) %>
                  </span>
                </div>
                <div id="dashboard-root-ungrouped" data-parent-id="" data-group="dashboard-nodes" data-event="reorder_nodes" data-handle=".drag-handle" phx-hook="Sortable" class="flex flex-col" style="min-height: 14px;">
                  <%= for dashboard <- @ungrouped_dashboards do %>
                    <%= render_dashboard(%{dashboard: dashboard, level: 0}) %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Modals -->
      <.app_modal :if={@live_action == :new} id="dashboard-modal" show on_cancel={JS.patch(~p"/app/dbs/#{@database.id}/dashboards")}>
        <:title>New Dashboard</:title>
        <:body>
          <.live_component
            module={TrifleApp.DatabaseDashboardsLive.FormComponent}
            id={@dashboard.id || :new}
            action={@live_action}
            dashboard={@dashboard}
            database={@database}
            current_user={@current_user}
            patch={~p"/app/dbs/#{@database.id}/dashboards"}
          />
        </:body>
      </.app_modal>
    </div>
    """
  end

  # Components for nested groups and dashboards
  attr :node, :map, required: true
  attr :level, :integer, required: true
  attr :database, :map, required: true
  attr :editing_group_id, :string, default: nil
  attr :collapsed_groups, :any, default: nil
  defp render_group(assigns) do
    ~H"""
    <div data-id={@node.group.id} data-type="group">
      <div 
        class="flex items-center justify-between pr-0 py-2 border-b border-gray-100 dark:border-slate-700 hover:bg-gray-50 dark:hover:bg-slate-700/50 cursor-pointer"
        style={"padding-left: #{max(@level, 0) * 12 + 12}px"}
        data-group-header={@node.group.id}
        phx-click="toggle_group"
        phx-value-id={@node.group.id}
      >
        <%= if @editing_group_id == @node.group.id do %>
          <div class="flex items-center gap-2 w-full">
            <div class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4" fill="none"><path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18"/></svg>
            </div>
            <.form for={%{}} as={:g} phx-submit="rename_group" class="flex items-center gap-2 w-full">
              <input type="hidden" name="id" value={@node.group.id} />
              <input type="text" name="name" value={@node.group.name} class="w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-800 dark:text-white text-sm px-2 py-1" />
              <button type="submit" class="inline-flex items-center rounded-md bg-teal-600 px-2 py-1 text-xs font-semibold text-white shadow-sm hover:bg-teal-500">Save</button>
              <button type="button" phx-click="cancel_rename_group" class="inline-flex items-center rounded-md bg-gray-200 dark:bg-slate-600 px-2 py-1 text-xs font-semibold text-gray-800 dark:text-white shadow-sm hover:bg-gray-300 dark:hover:bg-slate-500">Cancel</button>
            </.form>
          </div>
        <% else %>
          <div class="flex items-center gap-2">
            <span class="text-gray-400 dark:text-slate-500" aria-hidden="true">
              <%= if MapSet.member?((@collapsed_groups || MapSet.new()), @node.group.id) do %>
                <!-- Chevron Right -->
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4"><path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7"/></svg>
              <% else %>
                <!-- Chevron Down -->
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7"/></svg>
              <% end %>
            </span>
            <!-- Folder icon -->
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4 text-gray-500 dark:text-slate-400">
              <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z" />
            </svg>
            <div class="font-medium text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400"><%= @node.group.name %></div>
            <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
              <%= length(@node.children) + length(@node.dashboards) %>
            </span>
          </div>
          <div class="flex items-center gap-3 mr-3" phx-click="noop">
            <button type="button" phx-click="new_group" phx-value-parent_id={@node.group.id} title="New subgroup" class="text-gray-600 dark:text-slate-400 hover:text-gray-900 dark:hover:text-white">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z" />
              </svg>
            </button>
            <button type="button" phx-click="start_rename_group" phx-value-id={@node.group.id} title="Rename" class="text-gray-600 dark:text-slate-400 hover:text-gray-900 dark:hover:text-white">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
              </svg>
            </button>
            <button type="button" phx-click="delete_group" phx-value-id={@node.group.id} data-confirm="Delete this group? Children will move up one level." title="Delete" class="text-red-600 dark:text-red-400 hover:text-red-900 dark:hover:text-red-300">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
              </svg>
            </button>
            <!-- Drag handle to the far right -->
            <div class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" />
              </svg>
            </div>
          </div>
        <% end %>
      </div>
      <%= unless MapSet.member?((@collapsed_groups || MapSet.new()), @node.group.id) do %>
        <div id={"group-" <> @node.group.id <> "-nodes"} data-parent-id={@node.group.id} data-group="dashboard-nodes" data-event="reorder_nodes" data-handle=".drag-handle" phx-hook="Sortable" class="flex flex-col" style="min-height: 14px;">
          <%= for entry <- mixed_group_nodes(@node) do %>
            <%= case entry do %>
              <% {:group, child} -> %>
                <%= render_group(%{node: child, level: @level + 1, database: @database, editing_group_id: @editing_group_id, collapsed_groups: @collapsed_groups}) %>
              <% {:dashboard, dashboard} -> %>
                <%= render_dashboard(%{dashboard: dashboard, level: @level + 1}) %>
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :dashboard, Trifle.Organizations.Dashboard, required: true
  attr :level, :integer, default: 0
  defp render_dashboard(assigns) do
    ~H"""
    <div class="pr-0 py-3 group border-b border-gray-100 dark:border-slate-700 cursor-pointer hover:bg-gray-50 dark:hover:bg-slate-700/50 grid items-center" style={"padding-left: #{max(@level, 0) * 12 + 12}px; grid-template-columns: minmax(0,1fr) auto auto; column-gap: 1.5rem;"} data-id={@dashboard.id} data-type="dashboard" phx-click="dashboard_clicked" phx-value-id={@dashboard.id}>
      <div class="min-w-0">
        <div class={[
          "flex items-center gap-2",
          @level > 0 && "ml-6"
        ]}>
          <!-- Dashboard icon -->
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4 text-gray-500 dark:text-slate-400">
            <path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6" />
          </svg>
          <span class="text-base font-semibold text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400 truncate"><%= @dashboard.name %></span>
        </div>
      </div>
      <div class="justify-self-end mr-6">
        <%= if @dashboard.user do %>
          <div class="h-6 w-6" title={"Created by #{@dashboard.user.email}"}>
            <img src={gravatar_url(@dashboard.user.email)} class="h-6 w-6 rounded-full" />
          </div>
        <% end %>
      </div>
      <div class="flex items-center gap-2 justify-self-end mr-3">
        <!-- Visibility badge -->
        <span class={[
          "inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium ring-1 ring-inset",
          if(@dashboard.visibility,
            do: "bg-teal-50 text-teal-700 ring-teal-600/20 dark:bg-teal-900 dark:text-teal-200 dark:ring-teal-500/30",
            else: "bg-gray-100 text-gray-600 ring-gray-500/10 dark:bg-slate-700 dark:text-gray-300 dark:ring-slate-600/40"
          )
        ]} title={if(@dashboard.visibility, do: "Visible to everyone in organization", else: "Private") }>
          <%= if @dashboard.visibility do %>
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
              <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
            </svg>
          <% else %>
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
            </svg>
          <% end %>
        </span>

        <!-- Public link badge -->
        <span class={[
          "inline-flex items-center rounded-md px-1.5 py-0.5 text-xs font-medium ring-1 ring-inset",
          if(@dashboard.access_token,
            do: "bg-teal-50 text-teal-700 ring-teal-600/20 dark:bg-teal-900 dark:text-teal-200 dark:ring-teal-500/30",
            else: "bg-gray-100 text-gray-600 ring-gray-500/10 dark:bg-slate-700 dark:text-gray-300 dark:ring-slate-600/40"
          )
        ]} title={if(@dashboard.access_token, do: "Has public link", else: "No public link")}>
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-4 w-4">
            <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z" />
          </svg>
        </span>
        <!-- Drag handle -->
        <div class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5"><path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" /></svg>
        </div>
      </div>
    </div>
    """
  end
end
