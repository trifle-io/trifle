defmodule TrifleApp.DashboardsLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.Dashboard

  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization")}
  end

  def mount(
        _params,
        _session,
        %{assigns: %{current_user: user, current_membership: membership}} = socket
      ) do
    {:ok,
     socket
     |> assign(:page_title, "Dashboards")
     |> assign(:breadcrumb_links, ["Dashboards"])
     |> assign(:dashboards_count, Organizations.count_dashboards_for_membership(user, membership))
     |> assign(
       :dashboard_groups_count,
       Organizations.count_dashboard_groups_for_membership(membership)
     )
     |> assign(:groups_tree, Organizations.list_dashboard_tree_for_membership(user, membership))
     |> assign(
       :ungrouped_dashboards,
       Organizations.list_dashboards_for_membership(user, membership, nil)
     )
     |> assign(:editing_group_id, nil)
     |> assign(:collapsed_groups, MapSet.new())
     |> assign(:current_membership, membership)
     |> assign(:can_manage_dashboards, Organizations.membership_owner?(membership))}
  end

  def handle_params(params, _url, socket) do
    socket = apply_action(socket, socket.assigns.live_action, params)
    {:noreply, refresh_tree(socket)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:dashboard, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:dashboard, %Dashboard{})
    |> assign(
      :databases,
      Organizations.list_databases_for_org(socket.assigns.current_membership.organization_id)
    )
  end

  # No modal form events in global-only mode

  def handle_event("delete_dashboard", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    dashboard = Organizations.get_dashboard_for_membership!(membership, id)
    case Organizations.delete_dashboard_for_membership(dashboard, membership) do
      {:ok, _} ->
        {:noreply,
         socket
         |> refresh_tree()
         |> put_flash(:info, "Dashboard deleted successfully")}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You do not have permission to delete this dashboard")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Dashboard does not belong to this organization")}
    end
  end

  def handle_event("duplicate_dashboard", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    original = Organizations.get_dashboard_for_membership!(membership, id)
    current_user = socket.assigns.current_user
    if Organizations.can_clone_dashboard?(original, membership) do
      attrs = %{
        "database_id" => original.database_id,
        "name" => (original.name || "Dashboard") <> " (copy)",
        "key" => original.key || "dashboard",
        "payload" => original.payload || %{},
        "default_timeframe" =>
          original.default_timeframe || original.database.default_timeframe || "24h",
        "default_granularity" =>
          original.default_granularity || original.database.default_granularity || "1h",
        "visibility" => original.visibility,
        "group_id" => original.group_id,
        "position" =>
          Organizations.get_next_dashboard_position_for_membership(membership, original.group_id)
      }

      case Organizations.create_dashboard_for_membership(current_user, membership, attrs) do
        {:ok, _new_dash} ->
          {:noreply,
           socket
           |> refresh_tree()
           |> put_flash(:info, "Dashboard duplicated")}

        {:error, _cs} ->
          {:noreply, put_flash(socket, :error, "Could not duplicate dashboard")}
      end
    else
      {:noreply, put_flash(socket, :error, "You do not have permission to duplicate this dashboard")}
    end
  end

  def handle_event("dashboard_clicked", %{"id" => dashboard_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dashboards/#{dashboard_id}")}
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

    collapsed =
      if MapSet.member?(collapsed, id),
        do: MapSet.delete(collapsed, id),
        else: MapSet.put(collapsed, id)

    socket =
      socket
      |> assign(:collapsed_groups, collapsed)
      |> push_event("save_collapsed_groups", %{ids: MapSet.to_list(collapsed)})

    {:noreply, socket}
  end

  def handle_event("expand_all_groups", _params, socket) do
    socket =
      socket
      |> assign(:collapsed_groups, MapSet.new())
      |> push_event("save_collapsed_groups", %{ids: []})

    {:noreply, socket}
  end

  def handle_event("collapse_all_groups", _params, socket) do
    ids = socket.assigns.groups_tree |> all_group_ids()

    socket =
      socket
      |> assign(:collapsed_groups, MapSet.new(ids))
      |> push_event("save_collapsed_groups", %{ids: ids})

    {:noreply, socket}
  end

  def handle_event("create_dashboard", params, socket) do
    current_user = socket.assigns.current_user
    name = String.trim(to_string(Map.get(params, "name", "")))
    db_id = Map.get(params, "database_id") |> to_string()
    key = String.trim(to_string(Map.get(params, "key", "")))

    membership = socket.assigns.current_membership

    cond do
      name == "" ->
        {:noreply, put_flash(socket, :error, "Name is required")}

      db_id in [nil, ""] ->
        {:noreply, put_flash(socket, :error, "Database is required")}

      true ->
        db = Organizations.get_database_for_org!(membership.organization_id, db_id)

        attrs = %{
          "name" => name,
          "key" => if(key == "", do: "dashboard", else: key),
          "database_id" => db.id,
          "visibility" => false,
          "group_id" => nil,
          "default_timeframe" => db.default_timeframe || "24h",
          "default_granularity" => db.default_granularity || "1h",
          "position" => Organizations.get_next_dashboard_position_for_membership(membership, nil)
        }

        case Organizations.create_dashboard_for_membership(current_user, membership, attrs) do
          {:ok, _dash} ->
            {:noreply,
             socket
             |> put_flash(:info, "Dashboard created")
             |> push_patch(to: ~p"/dashboards")}

          {:error, _cs} ->
            {:noreply, put_flash(socket, :error, "Could not create dashboard")}
        end
    end
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
    membership = socket.assigns.current_membership
    if not Organizations.membership_owner?(membership) do
      {:noreply, put_flash(socket, :error, "Only organization owners can create groups")}
    else
    name = Map.get(params, "name", "New Group")
    parent_id = Map.get(params, "parent_id")
    pos = Organizations.get_next_dashboard_group_position_for_membership(membership, parent_id)
    attrs = %{"name" => name, "parent_group_id" => parent_id, "position" => pos}

    case Organizations.create_dashboard_group_for_membership(membership, attrs) do
      {:ok, _group} -> {:noreply, refresh_tree(socket)}
      {:error, _cs} -> {:noreply, put_flash(socket, :error, "Could not create group")}
    end
    end
  end

  def handle_event("rename_group", %{"id" => id, "name" => name}, socket) do
    membership = socket.assigns.current_membership
    if not Organizations.membership_owner?(membership) do
      {:noreply, put_flash(socket, :error, "Only organization owners can rename groups")}
    else
      group = Organizations.get_dashboard_group_for_membership!(membership, id)

      case Organizations.update_dashboard_group(group, %{name: name}) do
        {:ok, _} -> {:noreply, socket |> assign(:editing_group_id, nil) |> refresh_tree()}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not rename group")}
      end
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership
    if not Organizations.membership_owner?(membership) do
      {:noreply, put_flash(socket, :error, "Only organization owners can delete groups")}
    else
      group = Organizations.get_dashboard_group_for_membership!(membership, id)

      case Organizations.delete_dashboard_group(group) do
        {:ok, _} -> {:noreply, refresh_tree(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not delete group")}
      end
    end
  end

  # Reorder events from Sortable (mixed groups + dashboards)
  def handle_event(
        "reorder_nodes",
        %{
          "items" => items,
          "parent_id" => parent_id,
          "from_items" => from_items,
          "from_parent_id" => from_parent_id,
          "moved_id" => moved_id,
          "moved_type" => moved_type
        },
        socket
      ) do
    membership = socket.assigns.current_membership
    if not Organizations.membership_owner?(membership) do
      {:noreply, put_flash(socket, :error, "Only organization owners can reorder dashboards")}
    else
      p = normalize_parent(parent_id)
      fp = normalize_parent(from_parent_id)

      case Organizations.reorder_nodes_for_membership(
             membership,
             p,
             items,
             fp,
             from_items,
             moved_id,
             moved_type
           ) do
        {:ok, _} ->
          {:noreply, refresh_tree(socket)}

        {:error, :invalid_parent} ->
          {:noreply, put_flash(socket, :error, "Cannot move a group under its descendant")}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, "You do not have permission to reorder these dashboards")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to reorder")}
      end
    end
  end

  defp normalize_parent(""), do: nil
  defp normalize_parent(nil), do: nil
  defp normalize_parent(id), do: id

  defp refresh_tree(socket) do
    user = socket.assigns.current_user
    membership = socket.assigns.current_membership

    socket
    |> assign(:dashboards_count, Organizations.count_dashboards_for_membership(user, membership))
    |> assign(
      :dashboard_groups_count,
      Organizations.count_dashboard_groups_for_membership(membership)
    )
    |> assign(:groups_tree, Organizations.list_dashboard_tree_for_membership(user, membership))
    |> assign(
      :ungrouped_dashboards,
      Organizations.list_dashboards_for_membership(user, membership, nil)
    )
  end

  defp gravatar_url(email) do
    hash =
      email
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
      <!-- tabs removed in global-only mode -->

      <!-- Dashboards Index -->
      <div class="mb-6">
        <div class="bg-white dark:bg-slate-800 rounded-lg shadow">
          <div
            id="dashboards-header-controls"
            class="py-3.5 pl-4 pr-3 text-left text-sm font-semibold text-gray-900 dark:text-white sm:pl-3 border-b border-gray-100 dark:border-slate-700 flex items-center justify-between"
            phx-hook="FastTooltip"
          >
            <div class="flex items-center gap-2">
              <span>Dashboards</span>
              <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-1 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
                {@dashboards_count}
              </span>
            </div>
            <div class="flex items-center gap-2">
              <.link
                patch={~p"/dashboards/new"}
                aria-label="New Dashboard"
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
              >
                <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
                </svg>
                <span class="hidden md:inline">New Dashboard</span>
              </.link>
              <%= if @can_manage_dashboards do %>
                <button
                  type="button"
                  phx-click="new_group"
                  aria-label="New Group"
                  class="inline-flex items-center rounded-md bg-slate-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-slate-500"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="h-5 w-5 md:-ml-0.5 md:mr-1.5"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
                    />
                  </svg>
                  <span class="hidden md:inline">New Group</span>
                </button>
              <% end %>
              <button
                type="button"
                phx-click="expand_all_groups"
                data-tooltip="Expand All"
                class="inline-flex items-center rounded-md bg-white dark:bg-slate-800 border border-gray-300 dark:border-slate-600 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-5 w-5"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3.75 9.776c.112-.017.227-.026.344-.026h15.812c.117 0 .232.009.344.026m-16.5 0a2.25 2.25 0 0 0-1.883 2.542l.857 6a2.25 2.25 0 0 0 2.227 1.932H19.05a2.25 2.25 0 0 0 2.227-1.932l.857-6a2.25 2.25 0 0 0-1.883-2.542m-16.5 0V6A2.25 2.25 0 0 1 6 3.75h3.879a1.5 1.5 0 0 1 1.06.44l2.122 2.12a1.5 1.5 0 0 0 1.06.44H18A2.25 2.25 0 0 1 20.25 9v.776"
                  />
                </svg>
              </button>
              <button
                type="button"
                phx-click="collapse_all_groups"
                data-tooltip="Collapse All"
                class="inline-flex items-center rounded-md bg-white dark:bg-slate-800 border border-gray-300 dark:border-slate-600 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-5 w-5"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
                  />
                </svg>
              </button>
            </div>
          </div>

          <div class="divide-y divide-gray-100 dark:divide-slate-700">
            <%= if @dashboards_count == 0 and @dashboard_groups_count == 0 do %>
              <div class="py-16 text-center">
                <svg
                  class="mx-auto h-12 w-12 text-gray-400 dark:text-gray-500"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
                  />
                </svg>
                <h3 class="mt-3 text-base font-semibold text-gray-900 dark:text-white">
                  No dashboards yet
                </h3>
                <p class="mt-2 text-sm text-gray-600 dark:text-slate-400">
                  Ready to build? Open Explore to start analyzing data.
                </p>
              </div>
            <% else %>
              <div class="p-2" id="dashboard-root" phx-hook="DashboardGroupsCollapse">
                <!-- Top-level Groups -->
                <div
                  id="dashboard-root-groups"
                  data-parent-id=""
                  data-group="dashboard-nodes"
                  data-event="reorder_nodes"
                  data-handle=".drag-handle"
                  phx-hook="Sortable"
                  class="flex flex-col"
                  style="min-height: 14px;"
                >
                  <%= for node <- @groups_tree do %>
                    {render_group(%{
                      node: node,
                      level: 0,
                      editing_group_id: @editing_group_id,
                      collapsed_groups: @collapsed_groups,
                      can_manage_dashboards: @can_manage_dashboards,
                      current_membership: @current_membership
                    })}
                  <% end %>
                </div>
                
    <!-- Ungrouped Dashboards at bottom -->
                <div class="mt-6 pt-4 border-t border-gray-200 dark:border-slate-700">
                  <div
                    class="flex items-center gap-2 text-xs uppercase tracking-wide text-gray-500 dark:text-slate-400 px-2 mb-2"
                    data-group-header=""
                  >
                    <span>Ungrouped</span>
                    <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-0.5 text-[10px] font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
                      {length(@ungrouped_dashboards)}
                    </span>
                  </div>
                  <div
                    id="dashboard-root-ungrouped"
                    data-parent-id=""
                    data-group="dashboard-nodes"
                    data-event="reorder_nodes"
                    data-handle=".drag-handle"
                    phx-hook="Sortable"
                    class="flex flex-col"
                    style="min-height: 14px;"
                  >
                    <%= for dashboard <- @ungrouped_dashboards do %>
                      {render_dashboard(%{
                        dashboard: dashboard,
                        level: 0,
                        can_clone_dashboard: Organizations.can_clone_dashboard?(dashboard, @current_membership),
                        can_manage_dashboards: @can_manage_dashboards
                      })}
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
      
    <!-- New Dashboard Modal -->
      <.app_modal
        :if={@live_action == :new}
        id="dashboard-modal"
        show
        on_cancel={JS.patch(~p"/dashboards")}
      >
        <:title>New Dashboard</:title>
        <:body>
          <.form for={%{}} phx-submit="create_dashboard" class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                Name
              </label>
              <input
                type="text"
                name="name"
                required
                placeholder="e.g., Weekly Sales"
                class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                Database
              </label>
              <div class="grid grid-cols-1 sm:max-w-xs">
                <select
                  name="database_id"
                  required
                  class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                >
                  <%= for db <- @databases || [] do %>
                    <option value={db.id}>{db.display_name}</option>
                  <% end %>
                </select>
                <svg
                  viewBox="0 0 16 16"
                  fill="currentColor"
                  data-slot="icon"
                  aria-hidden="true"
                  class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
                >
                  <path
                    d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                    clip-rule="evenodd"
                    fill-rule="evenodd"
                  />
                </svg>
              </div>
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                Key (optional)
              </label>
              <input
                type="text"
                name="key"
                placeholder="e.g., sales.metrics"
                class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
              />
            </div>
            <div class="flex items-center justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click={JS.patch(~p"/dashboards")}
                class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
              >
                Create
              </button>
            </div>
          </.form>
        </:body>
      </.app_modal>
    </div>
    """
  end

  # Components for nested groups and dashboards
  attr :node, :map, required: true
  attr :level, :integer, required: true
  attr :editing_group_id, :string, default: nil
  attr :collapsed_groups, :any, default: nil

  defp render_group(assigns) do
    assigns =
      assigns
      |> Map.put_new(:can_manage_dashboards, false)
      |> Map.put_new(:current_membership, nil)

    ~H"""
    <div data-id={@node.group.id} data-type="group">
      <div
        class="group flex items-center justify-between pr-0 py-2 border-b border-gray-100 dark:border-slate-700 hover:bg-gray-50 dark:hover:bg-slate-700/50 cursor-pointer"
        style={"padding-left: #{max(@level, 0) * 12 + 12}px"}
        data-group-header={@node.group.id}
        phx-click="toggle_group"
        phx-value-id={@node.group.id}
      >
        <%= if @editing_group_id == @node.group.id do %>
          <div class="flex items-center gap-2 w-full">
            <div class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-4 w-4"
                fill="none"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" />
              </svg>
            </div>
            <.form for={%{}} as={:g} phx-submit="rename_group" class="flex items-center gap-2 w-full">
              <input type="hidden" name="id" value={@node.group.id} />
              <input
                type="text"
                name="name"
                value={@node.group.name}
                class="w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-800 dark:text-white text-sm px-2 py-1"
              />
              <button
                type="submit"
                class="inline-flex items-center rounded-md bg-teal-600 px-2 py-1 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="cancel_rename_group"
                class="inline-flex items-center rounded-md bg-gray-200 dark:bg-slate-600 px-2 py-1 text-xs font-semibold text-gray-800 dark:text-white shadow-sm hover:bg-gray-300 dark:hover:bg-slate-500"
              >
                Cancel
              </button>
            </.form>
          </div>
        <% else %>
          <div class="flex items-center gap-2">
            <span class="text-gray-400 dark:text-slate-500" aria-hidden="true">
              <%= if MapSet.member?((@collapsed_groups || MapSet.new()), @node.group.id) do %>
                <!-- Chevron Right -->
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
                </svg>
              <% else %>
                <!-- Chevron Down -->
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" />
                </svg>
              <% end %>
            </span>
            <!-- Folder icon -->
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              class="h-4 w-4 text-gray-500 dark:text-slate-400"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
              />
            </svg>
            <div class="font-medium text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400">
              {@node.group.name}
            </div>
            <span class="inline-flex items-center rounded-md bg-teal-50 dark:bg-teal-900 px-2 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30">
              {length(@node.children) + length(@node.dashboards)}
            </span>
          </div>
          <div class="flex items-center gap-2 mr-3" phx-click="noop">
            <%= if @can_manage_dashboards do %>
              <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto">
              <button
                type="button"
                phx-click="new_group"
                phx-value-parent_id={@node.group.id}
                title="New subgroup"
                aria-label="New subgroup"
                class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M12 10.5v6m3-3H9m4.06-7.19-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
                  />
                </svg>
              </button>
              <button
                type="button"
                phx-click="start_rename_group"
                phx-value-id={@node.group.id}
                title="Rename"
                aria-label="Rename group"
                class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0  0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0  0 1 3 18.75V8.25A2.25 2.25 0  0 1 5.25 6H10"
                  />
                </svg>
              </button>
              <button
                type="button"
                phx-click="delete_group"
                phx-value-id={@node.group.id}
                data-confirm="Delete this group? Children will move up one level."
                title="Delete"
                aria-label="Delete group"
                class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-red-600 dark:text-red-400 hover:bg-gray-50 dark:hover:bg-slate-700"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                  />
                </svg>
              </button>
            </div>
            <!-- Drag handle to the far right -->
              <div class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-5 w-5"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" />
                </svg>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
      <%= unless MapSet.member?((@collapsed_groups || MapSet.new()), @node.group.id) do %>
        <div
          id={"group-" <> @node.group.id <> "-nodes"}
          data-parent-id={@node.group.id}
          data-group="dashboard-nodes"
          data-event="reorder_nodes"
          data-handle=".drag-handle"
          phx-hook="Sortable"
          class="flex flex-col"
          style="min-height: 14px;"
        >
          <%= for entry <- mixed_group_nodes(@node) do %>
            <%= case entry do %>
              <% {:group, child} -> %>
              {render_group(%{
                node: child,
                level: @level + 1,
                editing_group_id: @editing_group_id,
                collapsed_groups: @collapsed_groups,
                can_manage_dashboards: @can_manage_dashboards,
                current_membership: @current_membership
              })}
              <% {:dashboard, dashboard} -> %>
                {render_dashboard(%{
                  dashboard: dashboard,
                  level: @level + 1,
                  can_clone_dashboard: Organizations.can_clone_dashboard?(dashboard, @current_membership),
                  can_manage_dashboards: @can_manage_dashboards
                })}
            <% end %>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

attr :dashboard, Trifle.Organizations.Dashboard, required: true
attr :level, :integer, default: 0
attr :can_clone_dashboard, :boolean, default: false
attr :can_manage_dashboards, :boolean, default: false

  defp render_dashboard(assigns) do
    ~H"""
    <div
      class="pr-0 py-3 group border-b border-gray-100 dark:border-slate-700 cursor-pointer hover:bg-gray-50 dark:hover:bg-slate-700/50 grid items-center"
      style={"padding-left: #{max(@level, 0) * 12 + 12}px; grid-template-columns: minmax(0,1fr) auto auto; column-gap: 1.5rem;"}
      data-id={@dashboard.id}
      data-type="dashboard"
      phx-click="dashboard_clicked"
      phx-value-id={@dashboard.id}
    >
      <div class="min-w-0">
        <div class={[
          "flex items-center gap-2",
          @level > 0 && "ml-6"
        ]}>
          <!-- Dashboard icon -->
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="h-4 w-4 text-gray-500 dark:text-slate-400"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M3.75 3v11.25A2.25 2.25 0 0 0 6 16.5h2.25M3.75 3h-1.5m1.5 0h16.5m0 0h1.5m-1.5 0v11.25A2.25 2.25 0 0 1 18 16.5h-2.25m-7.5 0h7.5m-7.5 0-1 3m8.5-3 1 3m0 0 .5 1.5m-.5-1.5h-9.5m0 0-.5 1.5M9 11.25v1.5M12 9v3.75m3-6v6"
            />
          </svg>
          <span class="text-base font-semibold text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400 truncate">
            {@dashboard.name}
          </span>
        </div>
      </div>
      <div class="justify-self-end mr-6">
        <%= if @dashboard.user do %>
          <div class="h-6 w-6" title={"Created by #{@dashboard.user.email}"}>
            <img src={gravatar_url(@dashboard.user.email)} class="h-6 w-6 rounded-full" />
          </div>
        <% end %>
      </div>
        <div class="flex items-center gap-2 justify-self-end mr-3" phx-click="noop">
        <div class="opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none group-hover:pointer-events-auto">
          <%= if @can_clone_dashboard do %>
            <button
              type="button"
              phx-click="duplicate_dashboard"
              phx-value-id={@dashboard.id}
              title="Duplicate dashboard"
              aria-label="Duplicate dashboard"
              class="inline-flex items-center justify-center rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-1.5 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700 mr-1"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-4 w-4"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75"
                />
              </svg>
            </button>
          <% end %>
        </div>
        <%= if @dashboard.visibility do %>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="h-4 w-4 text-teal-600 dark:text-teal-400"
            title="Visible to everyone in organization"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
            />
          </svg>
        <% else %>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="h-4 w-4 text-gray-400 dark:text-slate-500"
            title="Private"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z"
            />
          </svg>
        <% end %>

        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class={[
            "h-4 w-4",
            if(@dashboard.access_token,
              do: "text-teal-600 dark:text-teal-400",
              else: "text-gray-400 dark:text-slate-500"
            )
          ]}
          title={if(@dashboard.access_token, do: "Has public link", else: "No public link")}
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z"
          />
        </svg>
        <!-- Drag handle -->
            <%= if @can_manage_dashboards do %>
              <div class="drag-handle cursor-move text-gray-400 dark:text-slate-500 hover:text-gray-600 dark:hover:text-slate-300">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-5 w-5"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 8h18M3 16h18" />
              </svg>
            </div>
            <% end %>
      </div>
    </div>
    """
  end
end
