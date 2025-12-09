defmodule TrifleApp.DashboardLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Organizations.DashboardSegments
  alias Trifle.Stats.Source
  alias Trifle.Exports.Series, as: SeriesExport
  alias Phoenix.HTML
  alias TrifleApp.ExploreCore
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing
  alias Ecto.UUID
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: DashboardWidgetHelpers

  alias TrifleApp.Components.DashboardWidgets.{
    Category,
    Distribution,
    Kpi,
    Table,
    Text,
    Timeseries,
    WidgetData
  }

  alias TrifleApp.Components.DashboardWidgets.List, as: WidgetList
  require Logger

  def mount(%{"id" => _dashboard_id}, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(
        %{"id" => dashboard_id},
        _session,
        %{assigns: %{current_membership: membership}} = socket
      ) do
    dashboard = Organizations.get_dashboard_for_membership!(membership, dashboard_id)
    current_user = socket.assigns.current_user

    if current_user do
      Organizations.record_dashboard_visit(current_user, membership, dashboard)
    end

    socket = initialize_dashboard_state(socket, dashboard, membership, false, nil)

    groups = Organizations.get_dashboard_group_chain(dashboard.group_id)

    breadcrumbs =
      [{"Dashboards", "/dashboards"}] ++
        Enum.map(groups, &{&1.name, "/dashboards"}) ++ [dashboard.name]

    # Build page title with groups
    title_parts = ["Dashboards"] ++ Enum.map(groups, & &1.name) ++ [dashboard.name]
    page_title = Enum.join(title_parts, " · ")

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:breadcrumb_links, breadcrumbs)
     |> assign(:current_membership, membership)
     |> assign_dashboard_permissions()}
  end

  def mount_public(%{"dashboard_id" => dashboard_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:is_public_access, true)
     |> assign(:public_token, nil)
     |> assign(:dashboard_id, dashboard_id)}
  end

  def handle_params(params, url, socket) do
    if socket.assigns.is_public_access do
      handle_public_params(params, url, socket)
    else
      socket = apply_url_params(socket, params)

      socket =
        socket
        |> assign(:print_mode, params["print"] in ["1", "true", "yes"])
        |> apply_action(socket.assigns.live_action, params)

      {:noreply, socket}
    end
  end

  def handle_public_params(params, _url, socket) do
    token = params["token"]
    dashboard_id = socket.assigns.dashboard_id

    case Organizations.get_dashboard_by_token(dashboard_id, token) do
      {:ok, dashboard} ->
        socket =
          socket
          |> initialize_dashboard_state(dashboard, nil, true, token)
          |> apply_url_params(params)
          |> assign(:page_title, nil)
          |> assign(:breadcrumb_links, [])
          |> assign(:print_mode, params["print"] in ["1", "true", "yes"])
          |> then(fn s -> apply_action(s, socket.assigns.live_action, params) end)

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "Dashboard not found or invalid token")
         |> redirect(to: "/")}
    end
  end

  defp apply_action(socket, :show, _params) do
    if dashboard_has_key?(socket) do
      load_dashboard_data(socket)
    else
      socket
    end
  end

  defp apply_action(socket, :public, _params) do
    if dashboard_has_key?(socket) do
      load_dashboard_data(socket)
    else
      socket
    end
  end

  defp apply_action(socket, :configure, _params) do
    membership = socket.assigns.current_membership

    sources =
      membership
      |> Source.list_for_membership()
      |> ensure_source_in_list(socket.assigns.source)

    socket
    |> assign(:temp_name, socket.assigns.dashboard.name)
    |> assign(
      :temp_timeframe,
      socket.assigns.dashboard.default_timeframe || socket.assigns.database.default_timeframe ||
        "24h"
    )
    |> assign(:sources, sources)
    |> assign(:selected_source_ref, component_source_ref(socket.assigns.source))
    |> assign(:configure_segments, configure_segments_from_dashboard(socket.assigns.dashboard))
  end

  def handle_event("update_temp_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :temp_name, name)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    if !socket.assigns.can_edit_dashboard do
      {:noreply,
       put_flash(
         socket,
         :error,
         permission_message(socket, "You do not have permission to rename this dashboard")
       )}
    else
      dashboard = socket.assigns.dashboard
      membership = socket.assigns.current_membership

      case Organizations.update_dashboard_for_membership(dashboard, membership, %{name: name}) do
        {:ok, updated_dashboard} ->
          # Update breadcrumbs and page title with new dashboard name
          groups = Organizations.get_dashboard_group_chain(updated_dashboard.group_id)

          updated_breadcrumbs =
            [{"Dashboards", "/dashboards"}] ++
              Enum.map(groups, &{&1.name, "/dashboards"}) ++ [updated_dashboard.name]

          updated_page_title = "Dashboards · #{updated_dashboard.name}"

          {:noreply,
           socket
           |> assign_dashboard(updated_dashboard)
           |> assign(:temp_name, updated_dashboard.name)
           |> assign(:breadcrumb_links, updated_breadcrumbs)
           |> assign(:page_title, updated_page_title)
           |> put_flash(:info, "Dashboard name updated successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update dashboard name")}
      end
    end
  end

  def handle_event("toggle_visibility", _params, socket) do
    if !socket.assigns.can_manage_dashboard do
      {:noreply,
       put_flash(
         socket,
         :error,
         permission_message(socket, "You do not have permission to change visibility")
       )}
    else
      dashboard = socket.assigns.dashboard
      membership = socket.assigns.current_membership

      case Organizations.update_dashboard_for_membership(
             dashboard,
             membership,
             %{visibility: !dashboard.visibility}
           ) do
        {:ok, updated_dashboard} ->
          {:noreply,
           socket
           |> assign_dashboard(updated_dashboard)
           |> put_flash(:info, "Dashboard visibility updated successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update dashboard visibility")}
      end
    end
  end

  def handle_event("toggle_lock", _params, socket) do
    error_message =
      permission_message(socket, "You do not have permission to change the lock state")

    cond do
      !socket.assigns.can_manage_lock ->
        {:noreply, put_flash(socket, :error, error_message)}

      true ->
        dashboard = socket.assigns.dashboard
        membership = socket.assigns.current_membership
        desired_state = !(dashboard.locked || false)

        case Organizations.update_dashboard_for_membership(
               dashboard,
               membership,
               %{locked: desired_state}
             ) do
          {:ok, updated_dashboard} ->
            message =
              if updated_dashboard.locked do
                "Dashboard locked. Only the owner or organization admins can modify it."
              else
                "Dashboard unlocked. Members with access can edit it."
              end

            {:noreply,
             socket
             |> assign_dashboard(updated_dashboard)
             |> put_flash(:info, message)}

          {:error, :forbidden} ->
            {:noreply, put_flash(socket, :error, error_message)}

          {:error, :unauthorized} ->
            {:noreply, put_flash(socket, :error, error_message)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to update dashboard lock state")}
        end
    end
  end

  def handle_event("generate_public_token", _params, socket) do
    if !socket.assigns.can_manage_dashboard do
      {:noreply,
       put_flash(
         socket,
         :error,
         permission_message(socket, "You do not have permission to generate a public link")
       )}
    else
      dashboard = socket.assigns.dashboard

      case Organizations.generate_dashboard_public_token(dashboard) do
        {:ok, updated_dashboard} ->
          {:noreply,
           socket
           |> assign_dashboard(updated_dashboard)
           |> put_flash(:info, "Public link generated successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to generate public link")}
      end
    end
  end

  def handle_event("remove_public_token", _params, socket) do
    if !socket.assigns.can_manage_dashboard do
      {:noreply,
       put_flash(
         socket,
         :error,
         permission_message(socket, "You do not have permission to remove the public link")
       )}
    else
      dashboard = socket.assigns.dashboard

      case Organizations.remove_dashboard_public_token(dashboard) do
        {:ok, updated_dashboard} ->
          {:noreply,
           socket
           |> assign_dashboard(updated_dashboard)
           |> put_flash(:info, "Public link removed successfully")}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to remove public link")}
      end
    end
  end

  def handle_event(
        "change_dashboard_owner_selection",
        %{"dashboard_owner_membership_id" => membership_id},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:dashboard_owner_selection, normalize_selection(membership_id))
     |> assign(:dashboard_owner_error, nil)}
  end

  def handle_event(
        "change_dashboard_owner_selection",
        %{"value" => membership_id},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:dashboard_owner_selection, normalize_selection(membership_id))
     |> assign(:dashboard_owner_error, nil)}
  end

  def handle_event("transfer_dashboard_owner", _params, socket) do
    cond do
      !socket.assigns[:can_transfer_dashboard_owner] ->
        {:noreply,
         socket
         |> assign(:dashboard_owner_error, "You do not have permission to transfer ownership")}

      true ->
        selection = socket.assigns[:dashboard_owner_selection] || ""

        cond do
          selection == "" ->
            {:noreply,
             socket
             |> assign(:dashboard_owner_error, "Select a member to transfer ownership")}

          true ->
            dashboard = socket.assigns.dashboard
            membership = socket.assigns.current_membership

            case Organizations.transfer_dashboard_ownership(dashboard, membership, selection) do
              {:ok, updated_dashboard} ->
                new_owner = Organizations.get_membership!(selection)
                label = ownership_option_label(new_owner)

                {:noreply,
                 socket
                 |> assign(:dashboard_owner_selection, "")
                 |> assign(:dashboard_owner_error, nil)
                 |> assign_dashboard(updated_dashboard)
                 |> put_flash(:info, "Ownership transferred to #{label}")}

              {:error, :same_owner} ->
                {:noreply,
                 socket
                 |> assign(:dashboard_owner_error, "Select a different member")
                 |> assign_dashboard_owner_state()}

              {:error, :invalid_target} ->
                {:noreply,
                 socket
                 |> assign(
                   :dashboard_owner_error,
                   "Selected member is not part of this organization"
                 )
                 |> assign_dashboard_owner_state()}

              {:error, :forbidden} ->
                {:noreply,
                 socket
                 |> assign(
                   :dashboard_owner_error,
                   "You do not have permission to transfer ownership"
                 )}

              {:error, :unauthorized} ->
                {:noreply,
                 socket
                 |> assign(
                   :dashboard_owner_error,
                   "You do not have permission to transfer ownership"
                 )}

              {:error, :not_found} ->
                {:noreply,
                 socket
                 |> assign(:dashboard_owner_error, "Selected member was not found")
                 |> assign_dashboard_owner_state()}

              {:error, %Ecto.Changeset{}} ->
                {:noreply,
                 socket
                 |> assign(:dashboard_owner_error, "Unable to transfer ownership right now")
                 |> assign_dashboard_owner_state()}
            end
        end
    end
  end

  def handle_event("change_dashboard_owner_selection", params, socket) do
    case Map.get(params, "dashboard_owner_membership_id") do
      nil ->
        {:noreply, socket}

      membership_id ->
        {:noreply,
         socket
         |> assign(:dashboard_owner_selection, normalize_selection(membership_id))
         |> assign(:dashboard_owner_error, nil)}
    end
  end

  def handle_event("transfer_dashboard_owner", _params, socket) do
    cond do
      !socket.assigns[:can_transfer_dashboard_owner] ->
        {:noreply,
         socket
         |> assign(:dashboard_owner_error, "You do not have permission to transfer ownership")}

      true ->
        selection = socket.assigns[:dashboard_owner_selection] || ""

        cond do
          selection == "" ->
            {:noreply,
             socket
             |> assign(:dashboard_owner_error, "Select a member to transfer ownership")}

          true ->
            dashboard = socket.assigns.dashboard
            membership = socket.assigns.current_membership

            case Organizations.transfer_dashboard_ownership(dashboard, membership, selection) do
              {:ok, updated_dashboard} ->
                new_owner = Organizations.get_membership!(selection)
                label = ownership_option_label(new_owner)

                {:noreply,
                 socket
                 |> assign(:dashboard_owner_selection, "")
                 |> assign(:dashboard_owner_error, nil)
                 |> assign_dashboard(updated_dashboard)
                 |> put_flash(:info, "Ownership transferred to #{label}")}

              {:error, :same_owner} ->
                {:noreply,
                 socket
                 |> assign(:dashboard_owner_error, "Select a different member")
                 |> assign_dashboard_owner_state()}

              {:error, :invalid_target} ->
                {:noreply,
                 socket
                 |> assign(
                   :dashboard_owner_error,
                   "Selected member is not part of this organization"
                 )
                 |> assign_dashboard_owner_state()}

              {:error, :forbidden} ->
                {:noreply,
                 socket
                 |> assign(
                   :dashboard_owner_error,
                   "You do not have permission to transfer ownership"
                 )}

              {:error, :unauthorized} ->
                {:noreply,
                 socket
                 |> assign(
                   :dashboard_owner_error,
                   "You do not have permission to transfer ownership"
                 )}

              {:error, :not_found} ->
                {:noreply,
                 socket
                 |> assign(:dashboard_owner_error, "Selected member was not found")
                 |> assign_dashboard_owner_state()}

              {:error, %Ecto.Changeset{}} ->
                {:noreply,
                 socket
                 |> assign(:dashboard_owner_error, "Unable to transfer ownership right now")
                 |> assign_dashboard_owner_state()}
            end
        end
    end
  end

  def handle_event("delete_dashboard", _params, socket) do
    error_message =
      permission_message(socket, "You do not have permission to delete this dashboard")

    if !socket.assigns.can_manage_dashboard do
      {:noreply, put_flash(socket, :error, error_message)}
    else
      dashboard = socket.assigns.dashboard
      membership = socket.assigns.current_membership

      case Organizations.delete_dashboard_for_membership(dashboard, membership) do
        {:ok, _} ->
          {:noreply,
           socket
           |> push_navigate(to: ~p"/dashboards")
           |> put_flash(:info, "Dashboard deleted successfully")}

        {:error, :forbidden} ->
          {:noreply, put_flash(socket, :error, error_message)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete dashboard")}
      end
    end
  end

  def handle_event("duplicate_dashboard", _params, socket) do
    if !socket.assigns.can_clone_dashboard do
      {:noreply,
       put_flash(socket, :error, "You do not have permission to duplicate this dashboard")}
    else
      original = socket.assigns.dashboard
      current_user = socket.assigns.current_user
      membership = socket.assigns.current_membership

      source = socket.assigns.source

      default_timeframe =
        original.default_timeframe || Source.default_timeframe(source) || "24h"

      default_granularity =
        original.default_granularity ||
          Source.default_granularity(source) ||
          Source.available_granularities(source) |> List.first() || "1h"

      attrs = %{
        "name" => (original.name || "Dashboard") <> " (copy)",
        "key" => original.key || "dashboard",
        "payload" => original.payload || %{},
        "visibility" => original.visibility,
        "group_id" => original.group_id,
        "position" =>
          Organizations.get_next_dashboard_position_for_membership(membership, original.group_id),
        "source_type" => Atom.to_string(Source.type(source)),
        "source_id" => to_string(Source.id(source)),
        "default_timeframe" => default_timeframe,
        "default_granularity" => default_granularity,
        "database_id" =>
          if(Source.type(source) == :database, do: to_string(Source.id(source)), else: nil)
      }

      case Organizations.create_dashboard_for_membership(current_user, membership, attrs) do
        {:ok, new_dash} ->
          {:noreply,
           socket
           |> put_flash(:info, "Dashboard duplicated")
           |> push_navigate(to: ~p"/dashboards/#{new_dash.id}")}

        {:error, %Ecto.Changeset{} = changeset} ->
          message = changeset_error_message(changeset)
          {:noreply, put_flash(socket, :error, message || "Could not duplicate dashboard")}
      end
    end
  end

  # Persist Grid layout changes from client (GridStack)
  def handle_event("dashboard_grid_changed", %{"items" => items}, socket) do
    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:current_user]) ->
        {:noreply, socket}

      !socket.assigns.can_edit_dashboard ->
        {:noreply, socket}

      true ->
        dashboard = socket.assigns.dashboard
        existing = (dashboard.payload || %{})["grid"] || []
        by_id = Map.new(existing, fn i -> {to_string(i["id"]), i} end)

        merged =
          Enum.map(items, fn item ->
            id = to_string(item["id"])
            prev = Map.get(by_id, id, %{})
            Map.merge(prev, item)
          end)

        payload = Map.put(dashboard.payload || %{}, "grid", merged)

        membership = socket.assigns.current_membership

        case Organizations.update_dashboard_for_membership(
               dashboard,
               membership,
               %{payload: payload}
             ) do
          {:ok, updated_dashboard} ->
            # If stats are loaded, recompute KPI values (in case new widgets were added)
            socket = assign_dashboard(socket, updated_dashboard)

            items = updated_dashboard.payload["grid"] || []

            {:noreply, socket}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # Widget editing modal controls
  def handle_event("open_widget_editor", %{"id" => id}, socket) do
    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:current_user]) ->
        {:noreply, socket}

      !socket.assigns.can_edit_dashboard ->
        {:noreply, socket}

      true ->
        socket = ensure_widget_path_options(socket)
        items = socket.assigns.dashboard.payload["grid"] || []
        path_options = socket.assigns[:widget_path_options] || []

        widget =
          Enum.find(items, fn i -> to_string(i["id"]) == to_string(id) end)
          |> case do
            nil -> %{"id" => id, "title" => "", "type" => "kpi"}
            found -> Map.put_new(found, "type", "kpi")
          end
          |> maybe_auto_expand_widget_paths(path_options)

        {:noreply, assign(socket, :editing_widget, widget)}
    end
  end

  def handle_event("close_widget_editor", _params, socket) do
    {:noreply, assign(socket, :editing_widget, nil)}
  end

  def handle_event("expand_widget", %{"id" => id}, socket) do
    expanded =
      socket.assigns.dashboard
      |> find_dashboard_widget(id)
      |> case do
        nil -> nil
        widget -> build_expanded_widget(socket, widget)
      end

    {:noreply, assign(socket, :expanded_widget, expanded)}
  end

  def handle_event("close_expanded_widget", _params, socket) do
    {:noreply, assign(socket, :expanded_widget, nil)}
  end

  def handle_event("save_widget", params, socket) do
    %{"widget_id" => id} = params

    title =
      params
      |> Map.get("widget_title")
      |> case do
        nil -> current_editing_widget_title(socket, id)
        value -> value
      end
      |> Kernel.||("")
      |> to_string()
      |> String.trim()

    type = String.downcase(Map.get(params, "widget_type", "kpi"))

    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:current_user]) ->
        {:noreply, socket}

      !socket.assigns.can_edit_dashboard ->
        {:noreply, socket}

      true ->
        socket = ensure_widget_path_options(socket)
        path_options = socket.assigns[:widget_path_options] || []
        items = socket.assigns.dashboard.payload["grid"] || []

        updated =
          Enum.map(items, fn i ->
            if to_string(i["id"]) == to_string(id) do
              base = i |> Map.put("title", title) |> Map.put("type", type)

              case type do
                "kpi" ->
                  subtype =
                    DashboardWidgetHelpers.normalize_kpi_subtype(
                      Map.get(params, "kpi_subtype"),
                      i
                    )

                  base =
                    base
                    |> Map.put("path", Map.get(params, "kpi_path", ""))
                    |> Map.put("function", Map.get(params, "kpi_function", "mean"))
                    |> Map.put("size", Map.get(params, "kpi_size", "m"))
                    |> Map.put("subtype", subtype)

                  case subtype do
                    "split" ->
                      base
                      |> Map.put("split", true)
                      |> Map.put("diff", Map.has_key?(params, "kpi_diff"))
                      |> Map.put("timeseries", Map.has_key?(params, "kpi_timeseries"))
                      |> Map.delete("goal_target")
                      |> Map.delete("goal_progress")

                    "goal" ->
                      base
                      |> Map.put("split", false)
                      |> Map.put("diff", false)
                      |> Map.put("timeseries", false)
                      |> Map.put(
                        "goal_target",
                        Map.get(params, "kpi_goal_target", "") |> String.trim()
                      )
                      |> Map.put("goal_progress", Map.has_key?(params, "kpi_goal_progress"))
                      |> Map.put("goal_invert", Map.has_key?(params, "kpi_goal_invert"))

                    _ ->
                      base
                      |> Map.put("split", false)
                      |> Map.put("diff", false)
                      |> Map.put("timeseries", Map.has_key?(params, "kpi_timeseries"))
                      |> Map.delete("goal_target")
                      |> Map.delete("goal_progress")
                      |> Map.delete("goal_invert")
                  end

                "timeseries" ->
                  paths =
                    params
                    |> Map.get("ts_paths", Map.get(params, "ts_paths[]", []))
                    |> DashboardWidgetHelpers.normalize_timeseries_paths_param()

                  base
                  |> Map.put("paths", auto_expand_path_wildcards(paths, path_options))
                  |> Map.put(
                    "chart_type",
                    Map.get(params, "ts_chart_type", Map.get(i, "chart_type") || "line")
                  )
                  |> Map.put("stacked", Map.has_key?(params, "ts_stacked"))
                  |> Map.put("normalized", Map.has_key?(params, "ts_normalized"))
                  |> Map.put("legend", Map.has_key?(params, "ts_legend"))
                  |> Map.put("y_label", Map.get(params, "ts_y_label", ""))

                "category" ->
                  cat_paths_param =
                    params
                    |> Map.get("cat_paths", Map.get(params, "cat_paths[]", []))

                  cat_paths =
                    DashboardWidgetHelpers.normalize_category_paths_param(cat_paths_param)

                  fallback_path =
                    params
                    |> Map.get("cat_path", "")
                    |> to_string()
                    |> String.trim()

                  paths =
                    case cat_paths do
                      [] -> if(fallback_path == "", do: [], else: [fallback_path])
                      list -> list
                    end

                  expanded_paths = auto_expand_path_wildcards(paths, path_options)

                  primary_path =
                    expanded_paths
                    |> Enum.reject(&(&1 == ""))
                    |> List.first()
                    |> Kernel.||(fallback_path)

                  base
                  |> Map.put("paths", expanded_paths)
                  |> Map.put("path", primary_path)
                  |> Map.put(
                    "chart_type",
                    Map.get(params, "cat_chart_type", Map.get(i, "chart_type") || "bar")
                  )

                "table" ->
                  table_paths_param =
                    params
                    |> Map.get("table_paths", Map.get(params, "table_paths[]", []))

                  table_paths =
                    DashboardWidgetHelpers.normalize_table_paths_param(table_paths_param)

                  fallback_path =
                    params
                    |> Map.get("table_path", "")
                    |> to_string()
                    |> String.trim()

                  paths =
                    case table_paths do
                      [] -> if(fallback_path == "", do: [], else: [fallback_path])
                      list -> list
                    end

                  expanded_paths = auto_expand_path_wildcards(paths, path_options)

                  primary_path =
                    expanded_paths
                    |> Enum.reject(&(&1 == ""))
                    |> List.first()
                    |> Kernel.||(fallback_path)

                  base
                  |> Map.put("paths", expanded_paths)
                  |> Map.put("path", primary_path)

                "distribution" ->
                  dist_paths_param =
                    params
                    |> Map.get("dist_paths", Map.get(params, "dist_paths[]", []))

                  dist_paths =
                    DashboardWidgetHelpers.normalize_distribution_paths_param(dist_paths_param)

                  expanded_paths = auto_expand_path_wildcards(dist_paths, path_options)

                  primary_path =
                    expanded_paths
                    |> Enum.reject(&(&1 == ""))
                    |> List.first()
                    |> Kernel.||("")

                  designators =
                    DashboardWidgetHelpers.normalize_distribution_designators(
                      params,
                      Map.get(i, "designators") || i || %{}
                    )

                  mode =
                    DashboardWidgetHelpers.normalize_distribution_mode(
                      Map.get(params, "dist_mode", Map.get(i, "mode"))
                    )

                  legend =
                    params
                    |> Map.get("dist_legend", Map.get(i, "legend"))
                    |> DashboardWidgetHelpers.normalize_distribution_legend()

                  base
                  |> Map.put("paths", expanded_paths)
                  |> Map.put("path", primary_path)
                  |> Map.put("designators", designators)
                  |> Map.put("designator", Map.get(designators, "horizontal"))
                  |> Map.put("mode", mode)
                  |> Map.put("legend", legend)

                "list" ->
                  list_path =
                    params
                    |> Map.get("list_path", Map.get(i, "path"))
                    |> case do
                      nil ->
                        nil

                      value ->
                        value
                        |> to_string()
                        |> String.trim()
                        |> case do
                          "" -> nil
                          trimmed -> trimmed
                        end
                    end

                  limit =
                    params
                    |> Map.get("list_limit", Map.get(i, "limit"))
                    |> normalize_optional_positive_integer()

                  sort =
                    params
                    |> Map.get("list_sort", Map.get(i, "sort") || "desc")
                    |> normalize_list_sort()

                  label_strategy =
                    params
                    |> Map.get("list_label_strategy", Map.get(i, "label_strategy") || "short")
                    |> normalize_list_label_strategy()

                  base
                  |> Map.put("path", list_path)
                  |> Map.put("limit", limit)
                  |> Map.put("sort", sort)
                  |> Map.put("label_strategy", label_strategy)
                  |> Map.delete("empty_message")

                "text" ->
                  subtype =
                    Map.get(params, "text_subtype", i["subtype"] || "header")
                    |> DashboardWidgetHelpers.normalize_text_subtype()

                  color_id =
                    Map.get(params, "text_color", i["color"])
                    |> DashboardWidgetHelpers.normalize_text_color_id()

                  base =
                    base
                    |> Map.put("type", "text")
                    |> Map.put("subtype", subtype)
                    |> Map.put("color", color_id)
                    |> Map.delete("path")
                    |> Map.delete("function")
                    |> Map.delete("size")
                    |> Map.delete("split")
                    |> Map.delete("diff")
                    |> Map.delete("timeseries")
                    |> Map.delete("goal_target")
                    |> Map.delete("goal_progress")
                    |> Map.delete("goal_invert")
                    |> Map.delete("paths")
                    |> Map.delete("chart_type")
                    |> Map.delete("stacked")
                    |> Map.delete("normalized")
                    |> Map.delete("legend")
                    |> Map.delete("y_label")

                  case subtype do
                    "html" ->
                      base
                      |> Map.put("payload", Map.get(params, "text_payload", "") |> to_string())
                      |> Map.delete("subtitle")
                      |> Map.delete("alignment")
                      |> Map.delete("title_size")

                    _ ->
                      base
                      |> Map.put(
                        "title_size",
                        Map.get(params, "text_title_size", i["title_size"] || "large")
                        |> DashboardWidgetHelpers.normalize_text_title_size()
                      )
                      |> Map.put(
                        "alignment",
                        Map.get(params, "text_alignment", i["alignment"] || "center")
                        |> DashboardWidgetHelpers.normalize_text_alignment()
                      )
                      |> Map.put(
                        "subtitle",
                        Map.get(params, "text_subtitle", i["subtitle"] || "")
                        |> to_string()
                        |> String.trim()
                      )
                      |> Map.delete("payload")
                  end

                _ ->
                  base
              end
            else
              i
            end
          end)

        payload = Map.put(socket.assigns.dashboard.payload || %{}, "grid", updated)

        membership = socket.assigns.current_membership

        case Organizations.update_dashboard_for_membership(
               socket.assigns.dashboard,
               membership,
               %{payload: payload}
             ) do
          {:ok, dashboard} ->
            # After saving, recompute KPI values if stats already loaded
            socket =
              socket
              |> assign_dashboard(dashboard)
              |> assign(:editing_widget, nil)
              |> maybe_refresh_expanded_widget()
              |> refresh_widget_datasets()

            {:noreply,
             socket
             |> push_event("dashboard_grid_widget_updated", %{id: id, title: title})}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("change_widget_type", %{"widget_id" => id} = params, socket) do
    w = socket.assigns.editing_widget || %{"id" => id}

    normalized =
      params
      |> Map.get("widget_type", w["type"] || "kpi")
      |> to_string()
      |> String.downcase()

    title_param = Map.get(params, "widget_title")

    w =
      w
      |> Map.put("type", normalized)
      |> maybe_put_widget_title(title_param)

    w =
      case normalized do
        "text" ->
          w
          |> Map.put_new("subtype", "header")
          |> Map.put_new("color", "default")

        "list" ->
          w
          |> Map.put_new("limit", 20)
          |> Map.put_new("sort", "desc")
          |> Map.put_new("label_strategy", "short")

        "distribution" ->
          designators =
            DashboardWidgetHelpers.normalize_distribution_designators(
              params,
              Map.get(w, "designators") || w || %{}
            )

          mode =
            params
            |> Map.get("dist_mode", Map.get(w, "mode"))
            |> DashboardWidgetHelpers.normalize_distribution_mode()

          legend =
            params
            |> Map.get("dist_legend", w["legend"])
            |> DashboardWidgetHelpers.normalize_distribution_legend()

          w
          |> Map.put_new("paths", w["paths"] || [""])
          |> Map.put("mode", mode)
          |> Map.put("designators", designators)
          |> Map.put("designator", Map.get(designators, "horizontal"))
          |> Map.put("legend", legend)

        _ ->
          w
      end

    {:noreply, assign(socket, :editing_widget, w)}
  end

  def handle_event("set_kpi_function", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         func when not is_nil(func) <- param(params, "function") do
      update_editing_widget(socket, id, fn widget ->
        Map.put(widget, "function", normalize_kpi_function(func))
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_kpi_size", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         size when not is_nil(size) <- param(params, "size") do
      update_editing_widget(socket, id, fn widget ->
        Map.put(widget, "size", normalize_kpi_size(size))
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_ts_chart_type", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         type when not is_nil(type) <- param(params, "chart_type") do
      update_editing_widget(socket, id, fn widget ->
        Map.put(widget, "chart_type", normalize_ts_chart_type(type))
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_cat_chart_type", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         type when not is_nil(type) <- param(params, "chart_type") do
      update_editing_widget(socket, id, fn widget ->
        Map.put(widget, "chart_type", normalize_cat_chart_type(type))
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("change_text_subtype", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         subtype when not is_nil(subtype) <- param(params, "text_subtype") do
      w = socket.assigns.editing_widget || %{"id" => id}
      normalized = DashboardWidgetHelpers.normalize_text_subtype(subtype)

      w =
        w
        |> Map.put("subtype", normalized)
        |> Map.put_new("color", "default")

      {:noreply, assign(socket, :editing_widget, w)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("change_text_color", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         color when not is_nil(color) <- param(params, "color") do
      w = socket.assigns.editing_widget || %{"id" => id}
      normalized = DashboardWidgetHelpers.normalize_text_color_id(color)
      w = Map.put(w, "color", normalized)

      {:noreply, assign(socket, :editing_widget, w)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_text_title_size", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         value when not is_nil(value) <- param(params, "text_title_size") do
      update_editing_widget(socket, id, fn widget ->
        size = DashboardWidgetHelpers.normalize_text_title_size(value)
        Map.put(widget, "title_size", size)
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_text_alignment", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         value when not is_nil(value) <- param(params, "text_alignment") do
      update_editing_widget(socket, id, fn widget ->
        alignment = DashboardWidgetHelpers.normalize_text_alignment(value)
        Map.put(widget, "alignment", alignment)
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("change_kpi_subtype", params, socket) do
    with id when not is_nil(id) <- param(params, "widget_id"),
         subtype when not is_nil(subtype) <- param(params, "kpi_subtype") do
      w = socket.assigns.editing_widget || %{"id" => id}
      normalized = DashboardWidgetHelpers.normalize_kpi_subtype(subtype, w)
      {:noreply, assign(socket, :editing_widget, Map.put(w, "subtype", normalized))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(
        "timeseries_paths_update",
        %{"widget_id" => widget_id, "paths" => raw_paths},
        socket
      ) do
    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:editing_widget]) ->
        {:noreply, socket}

      to_string(socket.assigns.editing_widget["id"]) != to_string(widget_id) ->
        {:noreply, socket}

      true ->
        path_options = socket.assigns[:widget_path_options] || []
        paths = DashboardWidgetHelpers.normalize_timeseries_paths_for_edit(raw_paths)
        expanded_paths = auto_expand_path_wildcards(paths, path_options)
        widget = Map.put(socket.assigns.editing_widget, "paths", expanded_paths)
        {:noreply, assign(socket, :editing_widget, widget)}
    end
  end

  def handle_event(
        "category_paths_update",
        %{"widget_id" => widget_id, "paths" => raw_paths},
        socket
      ) do
    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:editing_widget]) ->
        {:noreply, socket}

      to_string(socket.assigns.editing_widget["id"]) != to_string(widget_id) ->
        {:noreply, socket}

      true ->
        path_options = socket.assigns[:widget_path_options] || []
        paths = DashboardWidgetHelpers.normalize_category_paths_for_edit(raw_paths)
        expanded_paths = auto_expand_path_wildcards(paths, path_options)

        primary_path =
          expanded_paths
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> List.first()
          |> case do
            nil -> ""
            value -> value
          end

        widget =
          socket.assigns.editing_widget
          |> Map.put("paths", expanded_paths)
          |> Map.put("path", primary_path)

        {:noreply, assign(socket, :editing_widget, widget)}
    end
  end

  def handle_event(
        "distribution_paths_update",
        %{"widget_id" => widget_id, "paths" => raw_paths},
        socket
      ) do
    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:editing_widget]) ->
        {:noreply, socket}

      to_string(socket.assigns.editing_widget["id"]) != to_string(widget_id) ->
        {:noreply, socket}

      true ->
        path_options = socket.assigns[:widget_path_options] || []

        paths =
          DashboardWidgetHelpers.normalize_distribution_paths_for_edit(raw_paths)

        expanded_paths = auto_expand_path_wildcards(paths, path_options)

        primary_path =
          expanded_paths
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> List.first()
          |> case do
            nil -> ""
            value -> value
          end

        widget =
          socket.assigns.editing_widget
          |> Map.put("paths", expanded_paths)
          |> Map.put("path", primary_path)

        {:noreply, assign(socket, :editing_widget, widget)}
    end
  end

  def handle_event("delete_widget", %{"id" => id}, socket) do
    cond do
      socket.assigns.is_public_access ->
        {:noreply, socket}

      is_nil(socket.assigns[:current_user]) ->
        {:noreply, socket}

      !socket.assigns.can_edit_dashboard ->
        {:noreply, socket}

      true ->
        items = socket.assigns.dashboard.payload["grid"] || []
        updated = Enum.reject(items, fn i -> to_string(i["id"]) == to_string(id) end)
        payload = Map.put(socket.assigns.dashboard.payload || %{}, "grid", updated)

        membership = socket.assigns.current_membership

        case Organizations.update_dashboard_for_membership(
               socket.assigns.dashboard,
               membership,
               %{payload: payload}
             ) do
          {:ok, dashboard} ->
            widget_id = to_string(id)

            socket =
              socket
              |> assign_dashboard(dashboard)
              |> assign(:editing_widget, nil)
              |> maybe_refresh_expanded_widget()
              |> refresh_widget_datasets()
              |> push_event("dashboard_grid_widget_deleted", %{id: widget_id})

            {:noreply, socket}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  defp find_dashboard_widget(nil, _id), do: nil

  defp find_dashboard_widget(%{payload: payload}, id) when is_map(payload) do
    id = to_string(id)
    grid_items = Map.get(payload, "grid") || []

    Enum.find(grid_items, fn item ->
      to_string(item["id"]) == id
    end)
  end

  defp find_dashboard_widget(_, _id), do: nil

  defp build_expanded_widget(socket, widget) when is_map(widget) do
    id = to_string(widget["id"])
    stats = socket.assigns[:stats]
    type = widget_type(widget)
    title = widget["title"] |> to_string() |> String.trim()

    base = %{
      widget_id: id,
      title: if(title == "", do: "Untitled Widget", else: title),
      type: type
    }

    cond do
      is_nil(stats) ->
        base

      type == "timeseries" ->
        stats
        |> Timeseries.dataset(widget)
        |> maybe_put_chart(base)

      type == "category" ->
        stats
        |> Category.dataset(widget)
        |> maybe_put_chart(base)

      type == "kpi" ->
        stats
        |> Kpi.dataset(widget)
        |> maybe_put_kpi_data(base)

      type == "table" ->
        stats
        |> Table.dataset(widget)
        |> case do
          nil -> base
          table_data -> Map.put(base, :table_data, table_data)
        end

      type == "list" ->
        stats
        |> WidgetList.dataset(widget)
        |> case do
          nil -> base
          list_data -> Map.put(base, :list_data, list_data)
        end

      type == "distribution" ->
        stats
        |> Distribution.datasets([widget])
        |> List.first()
        |> maybe_put_chart(base)

      type == "text" ->
        widget
        |> Text.widget()
        |> case do
          nil -> base
          text_data -> Map.put(base, :text_data, text_data)
        end

      true ->
        base
    end
  end

  defp build_expanded_widget(_socket, _widget), do: nil

  defp maybe_put_chart(nil, base), do: base
  defp maybe_put_chart(chart_map, base), do: Map.put(base, :chart_data, chart_map)

  defp maybe_put_kpi_data(nil, base), do: base

  defp maybe_put_kpi_data({value_map, visual_map}, base) do
    base
    |> Map.put(:chart_data, value_map)
    |> Map.put(:visual_data, visual_map)
  end

  defp widget_type(widget) do
    widget
    |> Map.get("type", "kpi")
    |> to_string()
    |> String.downcase()
  end

  defp maybe_refresh_expanded_widget(socket) do
    case socket.assigns[:expanded_widget] do
      %{widget_id: widget_id} ->
        case find_dashboard_widget(socket.assigns.dashboard, widget_id) do
          nil -> assign(socket, :expanded_widget, nil)
          widget -> assign(socket, :expanded_widget, build_expanded_widget(socket, widget))
        end

      _ ->
        socket
    end
  end

  # Filter bar message handling
  def handle_info({:filter_bar, {:filter_changed, changes}}, socket) do
    updated_socket =
      Enum.reduce(changes, socket, fn
        {:source, _value}, acc -> acc
        {:database_id, _value}, acc -> acc
        {:reload, _}, acc -> acc
        {:from, value}, acc -> assign(acc, :from, value)
        {:to, value}, acc -> assign(acc, :to, value)
        {:granularity, value}, acc -> assign(acc, :granularity, value)
        {:smart_timeframe_input, value}, acc -> assign(acc, :smart_timeframe_input, value)
        {:use_fixed_display, value}, acc -> assign(acc, :use_fixed_display, value)
        {_, _}, acc -> acc
      end)

    updated_socket =
      case determine_dashboard_source(changes, socket.assigns.sources) do
        nil ->
          updated_socket

        new_source ->
          {from, to, granularity, smart_timeframe_input, use_fixed_display} =
            get_default_timeframe_params(new_source)

          updated_socket
          |> apply_dashboard_source_change(new_source)
          |> assign(:from, from)
          |> assign(:to, to)
          |> assign(:granularity, granularity)
          |> assign(:smart_timeframe_input, smart_timeframe_input)
          |> assign(:use_fixed_display, use_fixed_display)
      end

    url_params = build_url_params(updated_socket)

    updated_socket =
      push_patch(updated_socket, to: build_dashboard_url(updated_socket, url_params))

    updated_socket =
      if dashboard_has_key?(updated_socket) do
        load_dashboard_data(updated_socket)
      else
        updated_socket
      end

    {:noreply, updated_socket}
  end

  # Progress message handling
  def handle_info({:loading_progress, progress_map}, socket) do
    {:noreply, assign(socket, :loading_progress, progress_map)}
  end

  def handle_info({:transponding, state}, socket) do
    {:noreply, assign(socket, :transponding, state)}
  end

  # Dashboard Data Management

  defp initialize_dashboard_state(socket, dashboard, membership, is_public_access, public_token) do
    {source, database} =
      case dashboard.source_type do
        "project" ->
          project = Organizations.get_project!(dashboard.source_id)
          {Source.from_project(project), nil}

        _ ->
          database =
            dashboard.database || Organizations.get_database!(dashboard.source_id)

          {Source.from_database(database), database}
      end

    sources =
      case membership do
        %OrganizationMembership{} = member -> Source.list_for_membership(member)
        _ -> []
      end

    sources = ensure_source_in_list(sources, source)
    selected_source_ref = component_source_ref(source)

    {from, to, granularity, smart_timeframe_input, use_fixed_display} =
      get_default_timeframe_params(source)

    database_config = Source.stats_config(source)
    available_granularities = get_available_granularities(source)

    {transponder_info, transponder_response_paths} =
      Source.transponders(source)
      |> build_transponder_info()

    socket
    |> assign(:database, database)
    |> assign(:source, source)
    |> assign(:sources, sources)
    |> assign(:selected_source_ref, selected_source_ref)
    |> assign_dashboard(dashboard)
    |> assign(:is_public_access, is_public_access)
    |> assign(:public_token, public_token)
    |> assign(:database_config, database_config)
    |> assign(:available_granularities, available_granularities)
    |> assign(:transponder_response_paths, transponder_response_paths)
    |> assign(:transponder_info, transponder_info)
    |> assign(:from, from)
    |> assign(:to, to)
    |> assign(:granularity, granularity)
    |> assign(:smart_timeframe_input, smart_timeframe_input)
    |> assign(:use_fixed_display, use_fixed_display)
    |> assign(:stats, nil)
    |> assign(:timeline, "[]")
    |> assign(:transponder_results, %{successful: [], failed: [], errors: []})
    |> assign(:transponder_errors, [])
    |> assign(:show_error_modal, false)
    |> assign(:loading, false)
    |> assign(:loading_chunks, false)
    |> assign(:loading_progress, nil)
    |> assign(:transponding, false)
    |> assign(:load_duration_microseconds, nil)
    |> assign(:editing_widget, nil)
    |> assign(:show_export_dropdown, false)
    |> assign(:widget_path_options, [])
    |> assign(:widget_path_options_loaded, false)
    |> assign(:expanded_widget, nil)
    |> assign(:widget_kpi_values, %{})
    |> assign(:widget_kpi_visuals, %{})
    |> assign(:widget_timeseries, %{})
    |> assign(:widget_category, %{})
    |> assign(:widget_text, %{})
    |> assign(:widget_table, %{})
    |> assign(:widget_list, %{})
    |> assign(:widget_distribution, %{})
    |> assign_dashboard_permissions()
  end

  defp apply_url_params(socket, params) do
    # Parse URL parameters for filters
    config = socket.assigns.database_config

    defaults = %{
      default_timeframe:
        socket.assigns.dashboard.default_timeframe ||
          Source.default_timeframe(socket.assigns.source) ||
          "24h",
      default_granularity:
        socket.assigns.dashboard.default_granularity ||
          Source.default_granularity(socket.assigns.source) ||
          "1h"
    }

    {from, to, granularity, smart_timeframe_input, use_fixed_display} =
      UrlParsing.parse_url_params(
        params,
        config,
        socket.assigns.available_granularities,
        defaults
      )

    socket =
      socket
      |> assign(:from, from)
      |> assign(:to, to)
      |> assign(:granularity, granularity)
      |> assign(:smart_timeframe_input, smart_timeframe_input)
      |> assign(:use_fixed_display, use_fixed_display)

    segment_params = Map.get(params, "segments") || %{}

    assign_segment_state(socket, segment_params)
  end

  defp get_default_timeframe_params(source) do
    config = Source.stats_config(source)
    granularities = get_available_granularities(source)

    # Use source defaults if present
    default_tf = Source.default_timeframe(source) || "24h"
    default_gran = Source.default_granularity(source) || "1h"

    case TimeframeParsing.parse_smart_timeframe(default_tf, config) do
      {:ok, from, to, smart_input, use_fixed} ->
        gran =
          if Enum.member?(granularities, default_gran),
            do: default_gran,
            else: Enum.at(granularities, 3, "1h")

        {from, to, gran, smart_input, use_fixed}

      {:error, _} ->
        # Fallback
        now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
        from = DateTime.add(now, -24 * 60 * 60, :second)
        {from, now, "1h", "24h", false}
    end
  end

  defp get_available_granularities(source) do
    Source.available_granularities(source)
  end

  def dashboard_has_key?(socket) when is_struct(socket, Phoenix.LiveView.Socket) do
    case socket.assigns.dashboard.key do
      nil -> false
      "" -> false
      _key -> true
    end
  end

  def dashboard_has_key?(assigns) when is_map(assigns) do
    case assigns.dashboard.key do
      nil -> false
      "" -> false
      _key -> true
    end
  end

  defp load_dashboard_data(socket) do
    if dashboard_has_key?(socket) do
      socket =
        assign(socket,
          load_start_time: System.monotonic_time(:microsecond),
          loading: true,
          loading_chunks: true,
          loading_progress: nil,
          transponding: false
        )

      # Extract values to avoid async socket warnings
      source = socket.assigns.source
      key = socket.assigns.resolved_key || socket.assigns.dashboard.key
      key = key || ""
      granularity = socket.assigns.granularity
      from = socket.assigns.from
      to = socket.assigns.to
      # Capture LiveView PID before async task
      liveview_pid = self()

      start_async(socket, :dashboard_data_task, fn ->
        # Create progress callback to send updates back to LiveView
        progress_callback = fn progress_info ->
          case progress_info do
            {:chunk_progress, current, total} ->
              send(liveview_pid, {:loading_progress, %{current: current, total: total}})

            {:transponder_progress, :starting} ->
              send(liveview_pid, {:transponding, true})

            {:transponder_progress, :finished} ->
              send(liveview_pid, {:transponding, false})
          end
        end

        case Source.fetch_series(
               source,
               key,
               from,
               to,
               granularity,
               progress_callback: progress_callback
             ) do
          {:ok, result} -> result
          {:error, error} -> {:error, error}
        end
      end)
    else
      socket
    end
  end

  defp ensure_widget_path_options(%{assigns: %{widget_path_options_loaded: true}} = socket),
    do: socket

  defp ensure_widget_path_options(socket) do
    options = build_widget_path_options(socket.assigns)

    socket
    |> assign(:widget_path_options, options)
    |> assign(:widget_path_options_loaded, true)
  end

  defp build_widget_path_options(%{stats: %Trifle.Stats.Series{series: series_map}} = assigns) do
    table = Trifle.Stats.Tabler.tabulize(series_map)
    paths = table[:paths] || []
    transponder_info = Map.get(assigns, :transponder_info, %{})

    sorted_paths = Enum.sort(paths)

    Enum.map(sorted_paths, fn path ->
      label =
        path
        |> ExploreCore.format_nested_path(sorted_paths, transponder_info)
        |> HTML.safe_to_string()

      %{"value" => path, "label" => label}
    end)
  end

  defp build_widget_path_options(_assigns), do: []

  defp maybe_auto_expand_widget_paths(widget, options) when is_map(widget) do
    type = widget["type"] |> to_string() |> String.downcase()

    case type do
      "timeseries" ->
        paths =
          widget
          |> Map.get("paths", widget["path"])
          |> DashboardWidgetHelpers.normalize_timeseries_paths_for_edit()

        expanded = auto_expand_path_wildcards(paths, options)
        Map.put(widget, "paths", expanded)

      "category" ->
        paths =
          widget
          |> Map.get("paths", widget["path"])
          |> DashboardWidgetHelpers.normalize_category_paths_for_edit()
          |> auto_expand_path_wildcards(options)

        primary =
          paths
          |> Enum.reject(&(&1 == ""))
          |> List.first()
          |> Kernel.||(widget["path"] || "")

        widget
        |> Map.put("paths", paths)
        |> Map.put("path", primary)

      "table" ->
        paths =
          widget
          |> Map.get("paths", widget["path"])
          |> DashboardWidgetHelpers.normalize_table_paths_for_edit()
          |> auto_expand_path_wildcards(options)

        primary =
          paths
          |> Enum.reject(&(&1 == ""))
          |> List.first()
          |> Kernel.||(widget["path"] || "")

        widget
        |> Map.put("paths", paths)
        |> Map.put("path", primary)

      _ ->
        widget
    end
  end

  defp maybe_auto_expand_widget_paths(widget, _options), do: widget

  defp available_series_paths(%Trifle.Stats.Series{series: series_map}) when is_map(series_map) do
    case Trifle.Stats.Tabler.tabulize(series_map) do
      %{paths: paths} when is_list(paths) -> paths
      _ -> []
    end
  end

  defp available_series_paths(_), do: []

  defp auto_expand_path_wildcards(paths, options) when is_list(paths) do
    option_values = normalize_option_values(options)
    do_auto_expand_path_wildcards(paths, option_values)
  end

  defp auto_expand_path_wildcards(paths, _options) when is_list(paths),
    do: do_auto_expand_path_wildcards(paths, [])

  defp do_auto_expand_path_wildcards(paths, option_values) do
    Enum.reduce(paths, [], fn original, acc ->
      trimmed = original |> to_string() |> String.trim()

      expanded =
        cond do
          trimmed == "" -> ""
          String.contains?(trimmed, "*") -> trimmed
          Enum.any?(option_values, &String.starts_with?(&1, trimmed <> ".")) -> trimmed <> ".*"
          true -> trimmed
        end

      if expanded == "" do
        if Enum.any?(acc, &(&1 == "")), do: acc, else: acc ++ [expanded]
      else
        if Enum.any?(acc, &(&1 == expanded)), do: acc, else: acc ++ [expanded]
      end
    end)
  end

  defp normalize_option_values(options) do
    options
    |> Enum.map(&extract_option_value/1)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp extract_option_value(%{"value" => value}), do: to_option_string(value)
  defp extract_option_value(%{value: value}), do: to_option_string(value)
  defp extract_option_value(value), do: to_option_string(value)

  defp to_option_string(nil), do: ""
  defp to_option_string(value) when is_binary(value), do: value
  defp to_option_string(value) when is_atom(value), do: Atom.to_string(value)
  defp to_option_string(value), do: to_string(value)

  defp assign_dashboard_permissions(socket) do
    membership = socket.assigns[:current_membership]
    dashboard = socket.assigns[:dashboard]

    cond do
      match?(%Trifle.Organizations.Dashboard{}, dashboard) and
          match?(%Trifle.Organizations.OrganizationMembership{}, membership) ->
        can_manage = Organizations.can_manage_dashboard?(dashboard, membership)

        socket
        |> assign(:can_edit_dashboard, Organizations.can_edit_dashboard?(dashboard, membership))
        |> assign(:can_clone_dashboard, Organizations.can_clone_dashboard?(dashboard, membership))
        |> assign(:can_manage_dashboard, can_manage)
        |> assign(:can_manage_lock, can_manage)
        |> assign(:can_transfer_dashboard_owner, can_manage)

      true ->
        socket
        |> assign(:can_edit_dashboard, false)
        |> assign(:can_clone_dashboard, false)
        |> assign(:can_manage_dashboard, false)
        |> assign(:can_manage_lock, false)
        |> assign(:can_transfer_dashboard_owner, false)
    end
  end

  defp permission_message(socket, default_message) do
    if dashboard_locked_for_member?(socket) do
      "This dashboard is locked. Only the owner or organization admins can modify it."
    else
      default_message
    end
  end

  defp dashboard_locked_for_member?(%{assigns: assigns}) do
    dashboard = Map.get(assigns, :dashboard)
    can_manage = Map.get(assigns, :can_manage_dashboard, false)

    match?(%{locked: true}, dashboard) && !can_manage
  end

  defp assign_dashboard(socket, dashboard) do
    socket
    |> assign(:dashboard, dashboard)
    |> assign_dashboard_permissions()
    |> assign_dashboard_owner_state()
    |> assign_segment_state()
  end

  defp assign_dashboard_owner_state(%{assigns: assigns} = socket) do
    membership = assigns[:current_membership]
    dashboard = assigns[:dashboard]
    can_transfer = assigns[:can_transfer_dashboard_owner]

    previous_selection = Map.get(assigns, :dashboard_owner_selection, "")
    previous_error = Map.get(assigns, :dashboard_owner_error, nil)

    cond do
      !can_transfer || is_nil(dashboard) || is_nil(membership) ->
        socket
        |> assign(:dashboard_owner_candidates, [])
        |> assign(:dashboard_owner_selection, "")
        |> assign(:dashboard_owner_error, nil)

      true ->
        candidates =
          Organizations.list_memberships_for_org_id(membership.organization_id)
          |> Enum.reject(&(&1.user_id == dashboard.user_id))
          |> Enum.map(fn member ->
            %{
              id: member.id,
              label: ownership_option_label(member)
            }
          end)

        selection =
          if Enum.any?(candidates, &(&1.id == previous_selection)) do
            previous_selection
          else
            ""
          end

        socket
        |> assign(:dashboard_owner_candidates, candidates)
        |> assign(:dashboard_owner_selection, selection)
        |> assign(:dashboard_owner_error, if(candidates == [], do: nil, else: previous_error))
    end
  end

  defp assign_segment_state(socket, overrides \\ %{}) do
    dashboard = socket.assigns.dashboard
    raw_segments = dashboard.segments || []
    previous_values = Map.get(socket.assigns, :segment_values, %{})

    {segment_values, segments_with_current} =
      DashboardSegments.compute_state(raw_segments, overrides, previous_values)

    resolved_key =
      DashboardSegments.resolve_key(dashboard.key, segments_with_current, segment_values)

    socket
    |> assign(:dashboard_segments, segments_with_current)
    |> assign(:segment_values, segment_values)
    |> assign(:resolved_key, resolved_key)
  end

  defp compute_segment_state(segments, overrides, previous_values),
    do: DashboardSegments.compute_state(segments, overrides, previous_values)

  defp resolve_dashboard_key(pattern, segments, values_map),
    do: DashboardSegments.resolve_key(pattern, segments, values_map)

  defp ownership_option_label(%{user: user}) when is_map(user) do
    name = Map.get(user, :name) || Map.get(user, :full_name)

    cond do
      is_binary(name) and String.trim(name) != "" ->
        "#{name} (#{user.email})"

      true ->
        user.email
    end
  end

  defp normalize_selection(value) when value in [nil, ""], do: ""
  defp normalize_selection(value), do: to_string(value)

  defp fallback_select_value(_previous_present?, _previous_value, default_value, available_values) do
    cond do
      default_value not in [nil, ""] and default_value in available_values -> default_value
      available_values != [] -> hd(available_values)
      default_value in [nil, ""] -> default_value || ""
      true -> sanitize_select_value(default_value)
    end
  end

  defp resolve_default_value(nil, available_values) do
    case available_values do
      [] -> ""
      [first | _] -> first
    end
  end

  defp resolve_default_value("", available_values) do
    if available_values == [] do
      ""
    else
      ""
    end
  end

  defp resolve_default_value(value, available_values) do
    sanitized = sanitize_select_value(value)

    cond do
      sanitized == "" -> ""
      sanitized in available_values -> sanitized
      available_values == [] -> sanitized
      true -> hd(available_values)
    end
  end

  defp segment_select_values(segment) do
    segment
    |> Map.get("groups", [])
    |> Enum.flat_map(fn group ->
      group
      |> Map.get("items", [])
      |> Enum.map(fn item -> sanitize_select_value(Map.get(item, "value")) end)
    end)
  end

  defp segment_name(segment) do
    segment
    |> Map.get("name")
    |> case do
      nil -> ""
      value -> value |> to_string() |> String.trim()
    end
  end

  defp segment_type(segment) do
    segment
    |> Map.get("type", "select")
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "text" -> "text"
      "select" -> "select"
      "dropdown" -> "select"
      other when other == "" -> "select"
      other -> other
    end
  end

  defp normalize_segment_value_map(values), do: DashboardSegments.normalize_value_map(values)

  defp sanitize_select_value(nil), do: ""
  defp sanitize_select_value(value) when is_binary(value), do: value
  defp sanitize_select_value(value), do: to_string(value)

  defp sanitize_text_value(nil), do: ""
  defp sanitize_text_value(value) when is_binary(value), do: value
  defp sanitize_text_value(value), do: to_string(value)

  defp configure_segments_from_dashboard(%{segments: segments}) when is_list(segments) do
    segments
    |> deep_copy()
    |> normalize_configure_segments()
  end

  defp configure_segments_from_dashboard(_), do: []

  defp deep_copy(term), do: term |> :erlang.term_to_binary() |> :erlang.binary_to_term()

  defp merge_segment_form_params(segments, params) when is_list(segments) do
    params = params || %{}

    Enum.map(segments, fn segment ->
      id = segment["id"] |> to_string()
      segment_params = Map.get(params, id) || %{}
      update_segment_from_params(segment, segment_params)
    end)
  end

  defp merge_segment_form_params(segments, _params), do: segments

  defp update_segment_from_params(segment, params) do
    name = params |> Map.get("name", segment["name"]) |> sanitize_text_value()
    label = params |> Map.get("label", segment["label"]) |> sanitize_optional_text()
    type = params |> Map.get("type", segment["type"]) |> segment_type_from_param()

    placeholder =
      params |> Map.get("placeholder", segment["placeholder"]) |> sanitize_optional_text()

    default_value_param = Map.get(params, "default_value", segment["default_value"])

    updated =
      segment
      |> Map.put("name", name)
      |> Map.put("label", label)
      |> Map.put("type", type)
      |> Map.put("placeholder", placeholder)

    case type do
      "text" ->
        default_value = sanitize_text_value(default_value_param)

        updated
        |> Map.put("default_value", default_value)

      _ ->
        groups_params = Map.get(params, "groups") || %{}
        groups = merge_group_form_params(Map.get(segment, "groups", []), groups_params)
        default_value = sanitize_select_value(default_value_param)

        updated
        |> Map.put("groups", groups)
        |> Map.put("default_value", default_value)
    end
  end

  defp merge_group_form_params(groups, params) when is_list(groups) do
    Enum.map(groups, fn group ->
      id = group["id"] |> to_string()
      group_params = Map.get(params, id) || %{}
      update_group_from_params(group, group_params)
    end)
  end

  defp merge_group_form_params(groups, _params), do: groups

  defp update_group_from_params(group, params) do
    label = params |> Map.get("label", group["label"]) |> sanitize_optional_text()
    items_params = Map.get(params, "items") || %{}
    items = merge_item_form_params(Map.get(group, "items", []), items_params)

    group
    |> Map.put("label", label)
    |> Map.put("items", items)
  end

  defp merge_item_form_params(items, params) when is_list(items) do
    Enum.map(items, fn item ->
      id = item["id"] |> to_string()
      item_params = Map.get(params, id) || %{}
      update_item_from_params(item, item_params)
    end)
  end

  defp merge_item_form_params(items, _params), do: items

  defp update_item_from_params(item, params) do
    label = params |> Map.get("label", item["label"]) |> sanitize_optional_text()
    value = params |> Map.get("value", item["value"]) |> sanitize_select_value()

    item
    |> Map.put("label", label)
    |> Map.put("value", value)
  end

  defp sanitize_optional_text(nil), do: nil

  defp sanitize_optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp sanitize_optional_text(value),
    do: value |> to_string() |> String.trim() |> sanitize_optional_text()

  defp fetch_identifier(params, key) do
    params
    |> param_get(key)
    |> case do
      nil ->
        nil

      value ->
        value
        |> to_string()
        |> String.trim()
        |> case do
          "" -> nil
          trimmed -> trimmed
        end
    end
  end

  defp param_get(params, key) when is_map(params) do
    params[key] ||
      params[String.replace(key, "_", "-")] ||
      params[String.replace(key, "-", "_")]
  end

  defp param_get(_params, _key), do: nil

  defp segment_type_from_param(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "text" -> "text"
      _ -> "select"
    end
  end

  defp new_config_segment(type \\ "select") do
    id = UUID.generate()
    normalized_type = segment_type_from_param(type)

    base = %{
      "id" => id,
      "name" => "",
      "label" => "",
      "type" => normalized_type,
      "placeholder" => nil,
      "default_value" => if(normalized_type == "text", do: "", else: nil)
    }

    case normalized_type do
      "text" ->
        Map.put(base, "groups", [])

      _ ->
        Map.put(base, "groups", [new_config_group()])
    end
  end

  defp new_config_group do
    %{
      "id" => UUID.generate(),
      "label" => nil,
      "items" => [new_config_item()]
    }
  end

  defp new_config_item do
    %{
      "id" => UUID.generate(),
      "label" => "",
      "value" => ""
    }
  end

  defp update_segment_by_id(segments, segment_id, fun) do
    segments
    |> Enum.map(fn segment ->
      if to_string(segment["id"]) == to_string(segment_id) do
        fun.(segment)
      else
        segment
      end
    end)
  end

  defp update_group_by_id(segment, group_id, fun) do
    groups =
      segment
      |> Map.get("groups", [])
      |> Enum.map(fn group ->
        if to_string(group["id"]) == to_string(group_id) do
          fun.(group)
        else
          group
        end
      end)

    Map.put(segment, "groups", groups)
  end

  defp ensure_group_presence([]), do: [new_config_group()]
  defp ensure_group_presence(groups), do: groups

  defp ensure_item_presence([]), do: [new_config_item()]
  defp ensure_item_presence(items), do: items

  defp normalize_configure_segments(segments) when is_list(segments) do
    Enum.map(segments, &normalize_configure_segment/1)
  end

  defp normalize_configure_segments(other), do: other

  defp normalize_configure_segment(segment) do
    type = segment_type(segment)

    case type do
      "text" ->
        segment

      _ ->
        values = segment_select_values(segment)
        default = segment["default_value"] || ""

        normalized_default =
          cond do
            default == "" -> ""
            default in values -> default
            values != [] -> hd(values)
            true -> ""
          end

        Map.put(segment, "default_value", normalized_default)
    end
  end

  def build_url_params(%Phoenix.LiveView.Socket{} = socket), do: build_url_params(socket.assigns)

  def build_url_params(data) when is_map(data) do
    gran = Map.get(data, :granularity) || Map.get(data, "granularity") || "1h"

    timeframe =
      Map.get(data, :smart_timeframe_input) || Map.get(data, "smart_timeframe_input") ||
        Map.get(data, "timeframe") || "24h"

    use_fixed = Map.get(data, :use_fixed_display) || Map.get(data, "use_fixed_display") || false
    base = %{"granularity" => gran, "timeframe" => timeframe}

    params =
      if use_fixed do
        from = Map.get(data, :from) || Map.get(data, "from")
        to = Map.get(data, :to) || Map.get(data, "to")

        Map.merge(base, %{
          "from" => TimeframeParsing.format_for_datetime_input(from),
          "to" => TimeframeParsing.format_for_datetime_input(to)
        })
      else
        base
      end

    segment_values =
      data
      |> Map.get(:segment_values) || Map.get(data, "segment_values") ||
        %{}
        |> normalize_segment_value_map()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Enum.into(%{})

    params =
      Map.merge(params, source_params_map(Map.get(data, :source) || Map.get(data, "source")))

    if segment_values == %{} do
      params
    else
      Map.put(params, "segments", segment_values)
    end
  end

  def handle_async(:dashboard_data_task, {:ok, result}, socket) do
    # Calculate load duration
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time

    # Source.fetch_series returns %{series: stats, transponder_results: %{successful: [...], failed: [...], errors: [...]}}
    # Compute KPI values for existing widgets, if any
    socket =
      socket
      |> assign(loading: false)
      |> assign(loading_chunks: false)
      |> assign(loading_progress: nil)
      |> assign(transponding: false)
      |> assign(stats: result.series)
      |> assign(transponder_results: result.transponder_results)
      |> assign(widget_path_options: [])
      |> assign(widget_path_options_loaded: false)
      |> then(fn socket ->
        if socket.assigns.editing_widget do
          ensure_widget_path_options(socket)
        else
          socket
        end
      end)
      |> assign(load_duration_microseconds: load_duration)
      |> refresh_widget_datasets()
      |> maybe_refresh_expanded_widget()

    {:noreply, socket}
  end

  def handle_async(:dashboard_data_task, {:error, error}, socket) do
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time

    {:noreply,
     socket
     |> assign(loading: false)
     |> assign(loading_chunks: false)
     |> assign(loading_progress: nil)
     |> assign(transponding: false)
     |> assign(stats: nil)
     |> assign(load_duration_microseconds: load_duration)
     |> reset_widget_datasets()
     |> put_flash(:error, "Failed to load dashboard data: #{inspect(error)}")}
  end

  def handle_async(:dashboard_data_task, {:exit, reason}, socket) do
    IO.inspect(reason, label: "Dashboard data fetch failed")
    {:noreply, assign(socket, loading: false)}
  end

  defp refresh_widget_datasets(%{assigns: %{dashboard: nil}} = socket) do
    reset_widget_datasets(socket)
  end

  defp refresh_widget_datasets(socket) do
    stats = Map.get(socket.assigns, :stats)
    dashboard = Map.get(socket.assigns, :dashboard)
    datasets = WidgetData.datasets_from_dashboard(stats, dashboard)
    dataset_maps = WidgetData.dataset_maps(datasets)

    socket
    |> assign(:widget_kpi_values, dataset_maps.kpi_values)
    |> assign(:widget_kpi_visuals, dataset_maps.kpi_visuals)
    |> assign(:widget_timeseries, dataset_maps.timeseries)
    |> assign(:widget_category, dataset_maps.category)
    |> assign(:widget_text, dataset_maps.text)
    |> assign(:widget_table, dataset_maps.table)
    |> assign(:widget_list, dataset_maps.list)
    |> assign(:widget_distribution, dataset_maps.distribution)
  end

  defp reset_widget_datasets(socket) do
    socket
    |> assign(:widget_kpi_values, %{})
    |> assign(:widget_kpi_visuals, %{})
    |> assign(:widget_timeseries, %{})
    |> assign(:widget_category, %{})
    |> assign(:widget_text, %{})
    |> assign(:widget_table, %{})
    |> assign(:widget_list, %{})
    |> assign(:widget_distribution, %{})
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

  # Summary stats for footer (with transponder statistics)
  def get_summary_stats(assigns) do
    case assigns do
      %{
        dashboard: %{key: _key},
        resolved_key: resolved_key,
        stats: stats,
        transponder_info: transponder_info,
        transponder_results: transponder_results
      }
      when not is_nil(resolved_key) and resolved_key != "" and not is_nil(stats) ->
        # Count columns (timeline points)
        column_count = if stats.series[:at], do: length(stats.series[:at]), else: 0

        # Count paths (rows)
        path_count = if stats.series[:paths], do: length(stats.series[:paths]), else: 0

        # Use actual transponder results returned by Source.fetch_series
        successful_transponders = length(transponder_results.successful)
        failed_transponders = length(transponder_results.failed)
        transponder_errors = transponder_results.errors

        result = %{
          key: resolved_key,
          column_count: column_count,
          path_count: path_count,
          matching_transponders: successful_transponders + failed_transponders,
          successful_transponders: successful_transponders,
          failed_transponders: failed_transponders,
          transponder_errors: transponder_errors
        }

        # Debug logging to help troubleshoot
        IO.inspect(result, label: "Dashboard summary stats")
        result

      %{dashboard: %{key: _key}, resolved_key: resolved_key}
      when not is_nil(resolved_key) and resolved_key != "" ->
        # Dashboard has key but no stats loaded yet - show basic info
        result = %{
          key: resolved_key,
          column_count: 0,
          path_count: 0,
          matching_transponders: 0,
          successful_transponders: 0,
          failed_transponders: 0,
          transponder_errors: []
        }

        IO.inspect(result, label: "Dashboard summary stats (no data)")
        result

      assigns ->
        IO.inspect(
          %{
            has_dashboard: Map.has_key?(assigns, :dashboard),
            dashboard_key: assigns[:dashboard][:key],
            resolved_key: Map.get(assigns, :resolved_key),
            has_stats: Map.has_key?(assigns, :stats),
            stats_nil: is_nil(assigns[:stats]),
            has_transponder_results: Map.has_key?(assigns, :transponder_results)
          },
          label: "Dashboard summary stats conditions"
        )

        nil
    end
  end

  # Export helpers
  defp series_from_assigns(assigns), do: SeriesExport.extract_series(assigns[:stats])

  def handle_event("toggle_export_dropdown", _params, socket) do
    current = socket.assigns[:show_export_dropdown] || false

    {:noreply,
     socket
     |> assign(:show_export_dropdown, !current)}
  end

  def handle_event("hide_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, false)}
  end

  def handle_event("download_dashboard_csv", _params, socket) do
    series = series_from_assigns(socket.assigns)

    if SeriesExport.has_data?(series) do
      csv = SeriesExport.to_csv(series)
      fname = export_filename("dashboard", socket.assigns, ".csv")

      {:noreply,
       push_event(socket, "file_download", %{content: csv, filename: fname, type: "text/csv"})}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  def handle_event("download_dashboard_json", _params, socket) do
    series = series_from_assigns(socket.assigns)

    if SeriesExport.has_data?(series) do
      json = SeriesExport.to_json(series)
      fname = export_filename("dashboard", socket.assigns, ".json")

      {:noreply,
       push_event(socket, "file_download", %{
         content: json,
         filename: fname,
         type: "application/json"
       })}
    else
      {:noreply, put_flash(socket, :error, "No data to export")}
    end
  end

  defp export_filename(prefix, assigns, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)

    base =
      [prefix, assigns[:dashboard] && assigns.dashboard.name]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.replace(to_string(&1), ~r/[^a-zA-Z0-9_-]+/, "-"))
      |> Enum.join("-")

    if(base == "", do: prefix, else: base) <> "-" <> ts <> ext
  end

  def handle_event("download_dashboard_pdf", _params, socket) do
    # Prefer direct download via controller route to avoid large payloads over LiveView socket
    fname = export_filename("dashboard", socket.assigns, ".pdf")
    url = ~p"/export/dashboards/#{socket.assigns.dashboard.id}/pdf?filename=#{fname}"
    {:noreply, push_event(socket, "file_download_url", %{url: url, filename: fname})}
  end

  def handle_event("download_dashboard_png", _params, socket) do
    fname = export_filename("dashboard", socket.assigns, ".png")
    url = ~p"/export/dashboards/#{socket.assigns.dashboard.id}/png?filename=#{fname}"
    {:noreply, push_event(socket, "file_download_url", %{url: url, filename: fname})}
  end

  def handle_event("show_transponder_errors", _params, socket) do
    {:noreply, assign(socket, show_error_modal: true)}
  end

  def handle_event("hide_transponder_errors", _params, socket) do
    {:noreply, assign(socket, show_error_modal: false)}
  end

  def handle_event("reload_data", _params, socket) do
    reload_current_timeframe(socket)
  end

  def handle_event("update_segment_filters", %{"segments" => segments_params}, socket) do
    socket = assign_segment_state(socket, segments_params)
    params = build_url_params(socket.assigns)

    {:noreply,
     socket
     |> assign(loading: true)
     |> push_patch(to: build_dashboard_url(socket, params))}
  end

  def handle_event("update_segment_filters", _params, socket) do
    {:noreply, socket}
  end

  # Toggle Play/Pause from parent LiveView (in case event bubbles up)
  def handle_event("toggle_play_pause", _params, socket) do
    socket =
      if socket.assigns.use_fixed_display do
        # Switch to Play: recompute from/to from current smart timeframe, and mark as live (not fixed)
        tf = socket.assigns.smart_timeframe_input || "24h"
        config = socket.assigns.database_config

        case TimeframeParsing.parse_smart_timeframe(tf, config) do
          {:ok, from, to, smart, _use_fixed} ->
            assign(socket,
              from: from,
              to: to,
              smart_timeframe_input: smart,
              use_fixed_display: false
            )

          {:error, _} ->
            assign(socket, use_fixed_display: false)
        end
      else
        # Switch to Pause: keep current from/to and mark fixed
        assign(socket, use_fixed_display: true)
      end

    reload_current_timeframe(socket)
  end

  def handle_event("segments_editor_change", params, socket) do
    current_segments = socket.assigns.configure_segments || []
    segments_params = Map.get(params, "segments", %{})

    updated_segments =
      current_segments
      |> merge_segment_form_params(segments_params)
      |> normalize_configure_segments()

    socket =
      socket
      |> assign(:configure_segments, updated_segments)
      |> assign(:temp_timeframe, Map.get(params, "timeframe", socket.assigns[:temp_timeframe]))

    {:noreply, socket}
  end

  def handle_event("segments_add", _params, socket) do
    segments = socket.assigns.configure_segments || []

    updated_segments =
      (segments ++ [new_config_segment()])
      |> normalize_configure_segments()

    {:noreply, assign(socket, :configure_segments, updated_segments)}
  end

  def handle_event("segments_remove", %{"id" => segment_id}, socket) do
    segments = socket.assigns.configure_segments || []

    filtered =
      segments
      |> Enum.reject(fn segment -> segment["id"] == segment_id end)
      |> normalize_configure_segments()

    {:noreply, assign(socket, :configure_segments, filtered)}
  end

  def handle_event("segments_add_group", params, socket) do
    case fetch_identifier(params, "segment_id") do
      nil ->
        {:noreply, socket}

      segment_id ->
        segments = socket.assigns.configure_segments || []

        updated =
          update_segment_by_id(segments, segment_id, fn segment ->
            groups = Map.get(segment, "groups", []) ++ [new_config_group()]
            Map.put(segment, "groups", groups)
          end)
          |> normalize_configure_segments()

        {:noreply, assign(socket, :configure_segments, updated)}
    end
  end

  def handle_event("segments_remove_group", params, socket) do
    with segment_id when not is_nil(segment_id) <- fetch_identifier(params, "segment_id"),
         group_id when not is_nil(group_id) <- fetch_identifier(params, "group_id") do
      segments = socket.assigns.configure_segments || []

      updated =
        update_segment_by_id(segments, segment_id, fn segment ->
          groups =
            segment
            |> Map.get("groups", [])
            |> Enum.reject(&(&1["id"] == group_id))
            |> ensure_group_presence()

          Map.put(segment, "groups", groups)
        end)
        |> normalize_configure_segments()

      {:noreply, assign(socket, :configure_segments, updated)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("segments_add_item", params, socket) do
    with segment_id when not is_nil(segment_id) <- fetch_identifier(params, "segment_id"),
         group_id when not is_nil(group_id) <- fetch_identifier(params, "group_id") do
      segments = socket.assigns.configure_segments || []

      updated =
        update_segment_by_id(segments, segment_id, fn segment ->
          update_group_by_id(segment, group_id, fn group ->
            items = Map.get(group, "items", []) ++ [new_config_item()]
            Map.put(group, "items", items)
          end)
        end)
        |> normalize_configure_segments()

      {:noreply, assign(socket, :configure_segments, updated)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("segments_remove_item", params, socket) do
    with segment_id when not is_nil(segment_id) <- fetch_identifier(params, "segment_id"),
         group_id when not is_nil(group_id) <- fetch_identifier(params, "group_id"),
         item_id when not is_nil(item_id) <- fetch_identifier(params, "item_id") do
      segments = socket.assigns.configure_segments || []

      updated =
        update_segment_by_id(segments, segment_id, fn segment ->
          update_group_by_id(segment, group_id, fn group ->
            items =
              group
              |> Map.get("items", [])
              |> Enum.reject(&(&1["id"] == item_id))
              |> ensure_item_presence()

            Map.put(group, "items", items)
          end)
        end)
        |> normalize_configure_segments()

      {:noreply, assign(socket, :configure_segments, updated)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("save_settings", params, socket) do
    if !socket.assigns.can_edit_dashboard do
      {:noreply,
       put_flash(
         socket,
         :error,
         permission_message(socket, "You do not have permission to update this dashboard")
       )}
    else
      dashboard = socket.assigns.dashboard
      name = Map.get(params, "name")
      key = Map.get(params, "key")
      tf = Map.get(params, "timeframe")
      gran = Map.get(params, "granularity")
      source_ref = Map.get(params, "source_ref")

      segment_params = Map.get(params, "segments") || %{}

      configure_segments =
        socket.assigns.configure_segments
        |> List.wrap()
        |> merge_segment_form_params(segment_params)
        |> normalize_configure_segments()

      attrs = %{
        name: String.trim(to_string(name || "")),
        key: String.trim(to_string(key || "")),
        default_timeframe: String.trim(to_string(tf || "")),
        default_granularity: String.trim(to_string(gran || "")),
        segments: configure_segments
      }

      membership = socket.assigns.current_membership

      socket = assign(socket, :configure_segments, configure_segments)

      with {:ok, source} <-
             resolve_source_selection(
               source_ref,
               socket.assigns.source,
               socket.assigns.sources || [],
               membership
             ),
           {:ok, attrs} <- apply_source_to_attrs(attrs, source) do
        case Organizations.update_dashboard_for_membership(dashboard, membership, attrs) do
          {:ok, updated_dashboard} ->
            new_sources =
              membership
              |> Source.list_for_membership()
              |> ensure_source_in_list(source)

            socket =
              socket
              |> assign(:sources, new_sources)
              |> apply_dashboard_source_change(source)

            # Update breadcrumbs and title to reflect new name
            groups = Organizations.get_dashboard_group_chain(updated_dashboard.group_id)

            updated_breadcrumbs =
              [{"Dashboards", "/dashboards"}] ++
                Enum.map(groups, &{&1.name, "/dashboards"}) ++ [updated_dashboard.name]

            updated_page_title = "Dashboards · #{updated_dashboard.name}"

            {:noreply,
             socket
             |> assign_dashboard(updated_dashboard)
             |> assign(:temp_name, updated_dashboard.name)
             |> assign(
               :temp_timeframe,
               updated_dashboard.default_timeframe ||
                 socket.assigns.database.default_timeframe || "24h"
             )
             |> assign(:breadcrumb_links, updated_breadcrumbs)
             |> assign(:page_title, updated_page_title)
             |> assign(:configure_segments, configure_segments_from_dashboard(updated_dashboard))
             |> put_flash(:info, "Settings saved")
             |> push_patch(to: ~p"/dashboards/#{updated_dashboard.id}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to save settings")}
        end
      else
        {:error, message} ->
          {:noreply, put_flash(socket, :error, message)}
      end
    end
  end

  def handle_event("navigate_timeframe_backward", _params, socket) do
    navigate_timeframe(socket, :backward)
  end

  def handle_event("navigate_timeframe_forward", _params, socket) do
    navigate_timeframe(socket, :forward)
  end

  def format_duration(microseconds) when is_nil(microseconds), do: nil

  def format_duration(microseconds) when is_integer(microseconds) do
    cond do
      microseconds < 1_000 ->
        "#{microseconds}μs"

      microseconds < 1_000_000 ->
        ms = div(microseconds, 1_000)
        "#{ms}ms"

      microseconds < 60_000_000 ->
        seconds = div(microseconds, 1_000_000)
        "#{seconds}s"

      true ->
        minutes = div(microseconds, 60_000_000)
        "#{minutes}m"
    end
  end

  def render(assigns) do
    TrifleApp.Components.DashboardPage.dashboard(assigns)
  end

  defp reload_current_timeframe(socket) do
    granularity = socket.assigns.granularity

    params =
      if socket.assigns.use_fixed_display do
        %{
          "granularity" => granularity,
          "from" => TimeframeParsing.format_for_datetime_input(socket.assigns.from),
          "to" => TimeframeParsing.format_for_datetime_input(socket.assigns.to),
          "timeframe" => socket.assigns.smart_timeframe_input || "24h"
        }
      else
        %{
          "granularity" => granularity,
          "timeframe" => socket.assigns.smart_timeframe_input || "24h"
        }
      end

    {:noreply,
     socket
     |> assign(loading: true)
     |> push_patch(to: build_dashboard_url(socket, params))}
  end

  defp navigate_timeframe(socket, direction) do
    from = socket.assigns.from
    to = socket.assigns.to
    duration_seconds = DateTime.diff(to, from, :second)

    {new_from, new_to} =
      case direction do
        :backward ->
          new_from = DateTime.add(from, -duration_seconds, :second)
          {new_from, from}

        :forward ->
          proposed_to = DateTime.add(to, duration_seconds, :second)
          config = socket.assigns.database_config
          now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")

          if DateTime.compare(proposed_to, now) == :gt do
            clamped_to = now
            clamped_from = DateTime.add(clamped_to, -duration_seconds, :second)
            {clamped_from, clamped_to}
          else
            {to, proposed_to}
          end
      end

    params = %{
      "granularity" => socket.assigns.granularity,
      "from" => TimeframeParsing.format_for_datetime_input(new_from),
      "to" => TimeframeParsing.format_for_datetime_input(new_to),
      "timeframe" => "c"
    }

    {:noreply,
     socket
     |> assign(from: new_from, to: new_to, loading: true, smart_timeframe_input: "c")
     |> push_patch(to: build_dashboard_url(socket, params))}
  end

  defp build_transponder_info(transponders) do
    info =
      transponders
      |> Enum.map(fn transponder ->
        response_path = Map.get(transponder.config, "response_path", "")
        transponder_name = transponder.name || transponder.key
        if response_path != "", do: {response_path, transponder_name}, else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.into(%{})

    {info, Map.keys(info)}
  end

  defp determine_dashboard_source(changes, sources) do
    cond do
      Map.has_key?(changes, :source) ->
        source_from_change(changes.source, sources)

      (Map.has_key?(changes, :source_type) || Map.has_key?(changes, "source_type")) and
          (Map.has_key?(changes, :source_id) || Map.has_key?(changes, "source_id")) ->
        type = Map.get(changes, :source_type) || Map.get(changes, "source_type")
        id = Map.get(changes, :source_id) || Map.get(changes, "source_id")
        type_atom = parse_source_type(type)
        Source.find_in_list(sources, type_atom, id)

      Map.has_key?(changes, :database_id) ->
        Source.find_in_list(sources, :database, changes.database_id)

      true ->
        nil
    end
  end

  defp source_from_change(%{type: type, id: id}, sources) do
    type_atom = parse_source_type(type)
    Source.find_in_list(sources, type_atom, id)
  end

  defp source_from_change(%{"type" => type, "id" => id}, sources) do
    type_atom = parse_source_type(type)
    Source.find_in_list(sources, type_atom, id)
  end

  defp source_from_change(_other, _sources), do: nil

  defp resolve_source_selection(ref, current_source, sources, membership) do
    trimmed_ref = ref && String.trim(to_string(ref))

    cond do
      trimmed_ref in [nil, ""] ->
        if current_source do
          {:ok, current_source}
        else
          {:error, "Source is required"}
        end

      true ->
        with {:ok, {type_str, id}} <- parse_source_ref_string(trimmed_ref),
             type_atom when not is_nil(type_atom) <- parse_source_type(type_str),
             source when not is_nil(source) <-
               Source.find_in_list(sources, type_atom, id) ||
                 fetch_source(type_atom, id, membership) do
          {:ok, source}
        else
          _ -> {:error, "Selected source is not available"}
        end
    end
  end

  defp apply_source_to_attrs(attrs, source) do
    type = Source.type(source)
    id = source |> Source.id() |> to_string()

    attrs =
      attrs
      |> Map.put(:source_type, Atom.to_string(type))
      |> Map.put(:source_id, id)
      |> Map.put(:database_id, if(type == :database, do: id, else: nil))

    {:ok, attrs}
  end

  defp database_from_source(source) do
    case Source.type(source) do
      :database -> Source.record(source)
      _ -> nil
    end
  end

  defp source_params_map(nil), do: %{}

  defp source_params_map(source) do
    base = %{
      "source_type" => Atom.to_string(Source.type(source)),
      "source_id" => to_string(Source.id(source))
    }

    if Source.type(source) == :database do
      Map.put(base, "database_id", to_string(Source.id(source)))
    else
      base
    end
  end

  defp ensure_source_in_list(sources, source) do
    cond do
      is_nil(source) ->
        sources

      Enum.any?(sources, &source_same?(&1, source)) ->
        sources

      true ->
        (sources ++ [source])
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(fn s ->
          {source_sort_key(Source.type(s)), String.downcase(Source.display_name(s))}
        end)
    end
  end

  defp ensure_segment_params(socket, params) when is_map(params) do
    cond do
      Map.has_key?(params, "segments") ->
        params

      Map.has_key?(params, :segments) ->
        params

      true ->
        segment_values =
          socket.assigns
          |> Map.get(:segment_values, %{})
          |> normalize_segment_value_map()
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Enum.into(%{})

        if segment_values == %{} do
          params
        else
          Map.put(params, "segments", segment_values)
        end
    end
  end

  defp ensure_segment_params(_socket, params), do: params

  defp build_dashboard_url(socket, params) do
    params = ensure_segment_params(socket, params)

    cond do
      socket.assigns.is_public_access ->
        query =
          case socket.assigns.public_token do
            token when is_binary(token) and token != "" -> Map.put(params, "token", token)
            _ -> params
          end

        ~p"/d/#{socket.assigns.dashboard.id}?#{query}"

      true ->
        ~p"/dashboards/#{socket.assigns.dashboard.id}?#{params}"
    end
  end

  defp component_source_ref(nil), do: nil

  defp component_source_ref(source) do
    %{type: Source.type(source), id: to_string(Source.id(source))}
  end

  defp source_same?(a, b) do
    Source.type(a) == Source.type(b) && to_string(Source.id(a)) == to_string(Source.id(b))
  end

  defp source_sort_key(:database), do: 0
  defp source_sort_key(:project), do: 1
  defp source_sort_key(_other), do: 2

  defp parse_source_type(nil), do: nil
  defp parse_source_type(type) when is_atom(type), do: type

  defp parse_source_type(type) when is_binary(type) do
    case String.trim(type) do
      "" -> nil
      "database" -> :database
      "project" -> :project
      other -> String.to_atom(other)
    end
  rescue
    ArgumentError -> nil
  end

  defp parse_source_ref_string(ref) do
    case String.split(ref, ":", parts: 2) do
      [type, id] when id not in [nil, ""] -> {:ok, {type, id}}
      _ -> {:error, :invalid}
    end
  end

  defp fetch_source(:database, id, %OrganizationMembership{} = membership) do
    try do
      database = Organizations.get_database_for_org!(membership.organization_id, id)
      Source.from_database(database)
    rescue
      Ecto.NoResultsError -> nil
    end
  end

  defp fetch_source(:project, id, %OrganizationMembership{} = membership) do
    try do
      project = Organizations.get_project!(id)

      if project.user_id == membership.user_id do
        Source.from_project(project)
      else
        nil
      end
    rescue
      Ecto.NoResultsError -> nil
    end
  end

  defp fetch_source(_type, _id, _membership), do: nil

  defp changeset_error_message(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {message, _opts}} ->
      field = field |> to_string() |> String.replace("_", " ")
      String.capitalize("#{field} #{message}")
    end)
    |> List.first()
  end

  defp changeset_error_message(_), do: nil

  defp maybe_put_widget_title(widget, nil), do: widget

  defp maybe_put_widget_title(widget, title) do
    trimmed =
      title
      |> to_string()
      |> String.trim()

    Map.put(widget, "title", trimmed)
  end

  defp current_editing_widget_title(socket, id) do
    case socket.assigns[:editing_widget] do
      %{"id" => widget_id} = widget ->
        if to_string(widget_id) == to_string(id) do
          Map.get(widget, "title")
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp update_editing_widget(socket, id, updater) when is_function(updater, 1) do
    case fetch_editing_widget(socket, id) do
      {:ok, widget} ->
        updated = updater.(widget)
        {:noreply, assign(socket, :editing_widget, updated)}

      :error ->
        {:noreply, socket}
    end
  end

  defp fetch_editing_widget(socket, id) do
    widget = socket.assigns[:editing_widget]

    cond do
      is_nil(widget) -> :error
      is_nil(id) -> :error
      to_string(widget["id"]) != to_string(id) -> :error
      true -> {:ok, widget}
    end
  end

  defp normalize_ts_chart_type(value) do
    case value |> to_string() |> String.downcase() do
      "area" -> "area"
      "bar" -> "bar"
      _ -> "line"
    end
  end

  defp normalize_cat_chart_type(value) do
    case value |> to_string() |> String.downcase() do
      "pie" -> "pie"
      "donut" -> "donut"
      _ -> "bar"
    end
  end

  defp normalize_kpi_function(value) do
    case value |> to_string() |> String.downcase() do
      v when v in ["sum", "max", "min", "mean"] -> v
      _ -> "mean"
    end
  end

  defp normalize_kpi_size(value) do
    case value |> to_string() |> String.downcase() do
      v when v in ["s", "m", "l"] -> v
      _ -> "m"
    end
  end

  defp normalize_positive_integer(value, default \\ 1) do
    cond do
      is_integer(value) and value > 0 ->
        value

      is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> default
        end

      true ->
        default
    end
  end

  defp normalize_optional_positive_integer(value) do
    cond do
      value in [nil, "", false] ->
        nil

      is_integer(value) and value > 0 ->
        value

      is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp normalize_list_sort(value) do
    case value |> to_string() |> String.downcase() do
      v when v in ["asc", "alpha", "alpha_desc"] -> v
      _ -> "desc"
    end
  end

  defp normalize_list_label_strategy(value) do
    case value |> to_string() |> String.downcase() do
      "full_path" -> "full_path"
      _ -> "short"
    end
  end

  defp param(params, key) do
    Map.get(params, key) || Map.get(params, String.replace(key, "_", "-"))
  end

  defp apply_dashboard_source_change(socket, source) do
    {transponder_info, transponder_response_paths} =
      build_transponder_info(Source.transponders(source))

    database_config = Source.stats_config(source)
    available_granularities = get_available_granularities(source)

    socket
    |> assign(:source, source)
    |> assign(:sources, ensure_source_in_list(socket.assigns[:sources] || [], source))
    |> assign(:selected_source_ref, component_source_ref(source))
    |> assign(:database, database_from_source(source))
    |> assign(:database_config, database_config)
    |> assign(:available_granularities, available_granularities)
    |> assign(:transponder_info, transponder_info)
    |> assign(:transponder_response_paths, transponder_response_paths)
  end
end
