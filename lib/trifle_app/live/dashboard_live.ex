defmodule TrifleApp.DashboardLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.Source
  alias Phoenix.HTML
  alias TrifleApp.ExploreLive
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing
  alias Ecto.UUID
  import TrifleApp.Components.DashboardFooter, only: [dashboard_footer: 1]
  require Logger

  @text_widget_colors [
    %{id: "default", label: "Default (white)", background: "#ffffff", text: "#0f172a"},
    %{id: "slate", label: "Slate", background: "#0f172a", text: "#f8fafc"},
    %{id: "teal", label: "Teal", background: "#0f766e", text: "#ecfdf5"},
    %{id: "amber", label: "Amber", background: "#f59e0b", text: "#1f2937"},
    %{id: "emerald", label: "Emerald", background: "#10b981", text: "#064e3b"},
    %{id: "rose", label: "Rose", background: "#f43f5e", text: "#fff1f2"}
  ]

  @capture_group_regex ~r/\((?:\\.|[^()])*\)/
  @noncapturing_prefixes ["?:", "?=", "?!", "?<=", "?<!"]

  def mount(%{"id" => _dashboard_id}, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(
        %{"id" => dashboard_id},
        _session,
        %{assigns: %{current_membership: membership}} = socket
      ) do
    dashboard = Organizations.get_dashboard_for_membership!(membership, dashboard_id)
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

  def mount(%{"dashboard_id" => dashboard_id}, _session, socket) do
    {:ok,
     socket
     |> assign(:is_public_access, true)
     |> assign(:public_token, nil)
     |> assign(:dashboard_id, dashboard_id)}
  end

  def handle_params(params, _url, socket) do
    if socket.assigns.is_public_access do
      # Handle public access with token verification
      token = params["token"]
      dashboard_id = socket.assigns.dashboard_id

      case Organizations.get_dashboard_by_token(dashboard_id, token) do
        {:ok, dashboard} ->
          # Initialize dashboard data state for public access
          socket =
            initialize_dashboard_state(socket, dashboard, nil, true, token)

          socket = apply_url_params(socket, params)

          socket =
            socket
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
    else
      socket = apply_url_params(socket, params)

      socket =
        socket
        |> assign(:print_mode, params["print"] in ["1", "true", "yes"])
        |> apply_action(socket.assigns.live_action, params)

      {:noreply, socket}
    end
  end

  defp apply_action(socket, :show, _params) do
    socket =
      socket
      |> assign(:dashboard_changeset, nil)
      |> assign(:dashboard_form, nil)

    # Load dashboard data if key is configured
    if dashboard_has_key?(socket) do
      load_dashboard_data(socket)
    else
      socket
    end
  end

  defp apply_action(socket, :edit, _params) do
    changeset = Organizations.change_dashboard(socket.assigns.dashboard)

    socket
    |> assign(:dashboard_changeset, changeset)
    |> assign(:dashboard_form, to_form(changeset))
  end

  defp apply_action(socket, :public, _params) do
    socket =
      socket
      |> assign(:dashboard_changeset, nil)
      |> assign(:dashboard_form, nil)

    # Load dashboard data for public access too (if key configured)
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
    |> assign(:dashboard_changeset, nil)
    |> assign(:dashboard_form, nil)
    |> assign(:temp_name, socket.assigns.dashboard.name)
    |> assign(:sources, sources)
    |> assign(:selected_source_ref, component_source_ref(socket.assigns.source))
    |> assign(:configure_segments, configure_segments_from_dashboard(socket.assigns.dashboard))
  end

  def handle_event("update_temp_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :temp_name, name)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    if !socket.assigns.can_edit_dashboard do
      {:noreply, put_flash(socket, :error, "You do not have permission to rename this dashboard")}
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
    if !socket.assigns.can_edit_dashboard do
      {:noreply, put_flash(socket, :error, "You do not have permission to change visibility")}
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

  def handle_event("generate_public_token", _params, socket) do
    if !socket.assigns.can_edit_dashboard do
      {:noreply,
       put_flash(socket, :error, "You do not have permission to generate a public link")}
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
    if !socket.assigns.can_edit_dashboard do
      {:noreply,
       put_flash(socket, :error, "You do not have permission to remove the public link")}
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

  def handle_event("delete_dashboard", _params, socket) do
    if !socket.assigns.can_edit_dashboard do
      {:noreply, put_flash(socket, :error, "You do not have permission to delete this dashboard")}
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
          {:noreply,
           put_flash(socket, :error, "You do not have permission to delete this dashboard")}

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

  def handle_event("save_dashboard", %{"dashboard" => dashboard_params}, socket) do
    if !socket.assigns.can_edit_dashboard do
      {:noreply, put_flash(socket, :error, "You do not have permission to edit this dashboard")}
    else
      membership = socket.assigns.current_membership

      case Organizations.update_dashboard_for_membership(
             socket.assigns.dashboard,
             membership,
             dashboard_params
           ) do
        {:ok, dashboard} ->
          {:noreply,
           socket
           |> assign_dashboard(dashboard)
           |> assign(:dashboard_changeset, nil)
           |> assign(:dashboard_form, nil)
           |> push_patch(to: ~p"/dashboards/#{dashboard.id}")
           |> put_flash(:info, "Dashboard updated successfully")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           socket
           |> assign(:dashboard_changeset, changeset)
           |> assign(:dashboard_form, to_form(changeset))}
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

            socket =
              if socket.assigns[:stats] do
                {kpi_items, kpi_visuals} = compute_kpi_datasets(socket.assigns.stats, items)
                ts_items = compute_timeseries_widgets(socket.assigns.stats, items)
                cat_items = compute_category_widgets(socket.assigns.stats, items)

                socket
                |> push_event("dashboard_grid_kpi_values", %{items: kpi_items})
                |> push_event("dashboard_grid_kpi_visual", %{items: kpi_visuals})
                |> push_event("dashboard_grid_timeseries", %{items: ts_items})
                |> push_event("dashboard_grid_category", %{items: cat_items})
              else
                socket
              end

            text_items = compute_text_widgets(items)
            socket = push_event(socket, "dashboard_grid_text", %{items: text_items})

            {:noreply, socket}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:dashboard_changeset, nil)
     |> assign(:dashboard_form, nil)
     |> push_patch(to: ~p"/dashboards/#{socket.assigns.dashboard.id}")}
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
    title = String.trim(to_string(Map.get(params, "widget_title", "")))
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
                  subtype = normalize_kpi_subtype(Map.get(params, "kpi_subtype"), i)

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
                    |> normalize_timeseries_paths_param()

                  base
                  |> Map.put("paths", auto_expand_path_wildcards(paths, path_options))
                  |> Map.put("chart_type", Map.get(params, "ts_chart_type", "line"))
                  |> Map.put("stacked", Map.has_key?(params, "ts_stacked"))
                  |> Map.put("normalized", Map.has_key?(params, "ts_normalized"))
                  |> Map.put("legend", Map.has_key?(params, "ts_legend"))
                  |> Map.put("y_label", Map.get(params, "ts_y_label", ""))

                "category" ->
                  cat_paths_param =
                    params
                    |> Map.get("cat_paths", Map.get(params, "cat_paths[]", []))

                  cat_paths = normalize_category_paths_param(cat_paths_param)

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
                  |> Map.put("chart_type", Map.get(params, "cat_chart_type", "bar"))

                "text" ->
                  subtype =
                    Map.get(params, "text_subtype", i["subtype"] || "header")
                    |> normalize_text_subtype()

                  color_id =
                    Map.get(params, "text_color", i["color"]) |> normalize_text_color_id()

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
                        |> normalize_text_title_size()
                      )
                      |> Map.put(
                        "alignment",
                        Map.get(params, "text_alignment", i["alignment"] || "center")
                        |> normalize_text_alignment()
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

            socket =
              if socket.assigns[:stats] do
                items = dashboard.payload["grid"] || []
                {kpi_items, kpi_visuals} = compute_kpi_datasets(socket.assigns.stats, items)
                ts_items = compute_timeseries_widgets(socket.assigns.stats, items)
                cat_items = compute_category_widgets(socket.assigns.stats, items)

                socket
                |> push_event("dashboard_grid_kpi_values", %{items: kpi_items})
                |> push_event("dashboard_grid_kpi_visual", %{items: kpi_visuals})
                |> push_event("dashboard_grid_timeseries", %{items: ts_items})
                |> push_event("dashboard_grid_category", %{items: cat_items})
              else
                socket
              end

            {:noreply,
             socket
             |> push_event("dashboard_grid_widget_updated", %{id: id, title: title})}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("change_widget_type", %{"widget_id" => id, "widget_type" => type}, socket) do
    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = String.downcase(to_string(type))

    w = Map.put(w, "type", normalized)

    w =
      case normalized do
        "text" ->
          w
          |> Map.put_new("subtype", "header")
          |> Map.put_new("color", "default")

        _ ->
          w
      end

    {:noreply, assign(socket, :editing_widget, w)}
  end

  def handle_event("change_text_subtype", %{"widget_id" => id, "text_subtype" => subtype}, socket) do
    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = normalize_text_subtype(subtype)

    w =
      w
      |> Map.put("subtype", normalized)
      |> Map.put_new("color", "default")

    {:noreply, assign(socket, :editing_widget, w)}
  end

  def handle_event("change_text_subtype", %{"text_subtype" => subtype} = params, socket) do
    id =
      Map.get(params, "widget_id") ||
        Map.get(params, "widget-id") ||
        (socket.assigns.editing_widget && socket.assigns.editing_widget["id"])

    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = normalize_text_subtype(subtype)

    w =
      w
      |> Map.put("subtype", normalized)
      |> Map.put_new("color", "default")

    {:noreply, assign(socket, :editing_widget, w)}
  end

  def handle_event("change_text_color", %{"widget_id" => id, "color" => color_id}, socket) do
    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = normalize_text_color_id(color_id)
    w = Map.put(w, "color", normalized)

    {:noreply, assign(socket, :editing_widget, w)}
  end

  def handle_event("change_text_color", %{"color" => color_id} = params, socket) do
    id =
      Map.get(params, "widget_id") ||
        Map.get(params, "widget-id") ||
        (socket.assigns.editing_widget && socket.assigns.editing_widget["id"])

    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = normalize_text_color_id(color_id)
    w = Map.put(w, "color", normalized)

    {:noreply, assign(socket, :editing_widget, w)}
  end

  def handle_event("change_kpi_subtype", %{"widget_id" => id, "kpi_subtype" => subtype}, socket) do
    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = normalize_kpi_subtype(subtype, w)
    {:noreply, assign(socket, :editing_widget, Map.put(w, "subtype", normalized))}
  end

  def handle_event("change_kpi_subtype", %{"kpi_subtype" => subtype} = params, socket) do
    id =
      Map.get(params, "widget_id") ||
        Map.get(params, "widget-id") ||
        (socket.assigns.editing_widget && socket.assigns.editing_widget["id"])

    w = socket.assigns.editing_widget || %{"id" => id}
    normalized = normalize_kpi_subtype(subtype, w)
    {:noreply, assign(socket, :editing_widget, Map.put(w, "subtype", normalized))}
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
        paths = normalize_timeseries_paths_for_edit(raw_paths)
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
        paths = normalize_category_paths_for_edit(raw_paths)
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
            {:noreply,
             socket
             |> assign_dashboard(dashboard)
             |> assign(:editing_widget, nil)
             |> maybe_refresh_expanded_widget()
             |> push_event("dashboard_grid_widget_deleted", %{id: id})}

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # Compute KPI values for KPI widgets from current series
  defp normalize_kpi_subtype(value, item \\ %{}) do
    raw =
      case value do
        nil -> ""
        v -> to_string(v)
      end
      |> String.downcase()

    cond do
      raw in ["number", "split", "goal"] -> raw
      !!item["split"] -> "split"
      true -> "number"
    end
  end

  defp text_widget_color_options, do: @text_widget_colors

  defp default_text_widget_color do
    @text_widget_colors |> List.first()
  end

  defp resolve_text_widget_color(color_id) do
    id =
      case color_id do
        nil -> ""
        v -> to_string(v)
      end
      |> String.downcase()

    Enum.find(@text_widget_colors, &(&1.id == id)) || default_text_widget_color()
  end

  defp normalize_text_subtype(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "html" -> "html"
      "header" -> "header"
      _ -> "header"
    end
  end

  defp normalize_text_alignment(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "left" -> "left"
      "right" -> "right"
      _ -> "center"
    end
  end

  defp normalize_text_title_size(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "small" -> "small"
      "medium" -> "medium"
      "large" -> "large"
      "s" -> "small"
      "m" -> "medium"
      "l" -> "large"
      _ -> "large"
    end
  end

  defp normalize_text_color_id(value) do
    resolve_text_widget_color(value).id
  end

  defp compute_kpi_values(series_struct, grid_items) do
    compute_kpi_datasets(series_struct, grid_items) |> elem(0)
  end

  defp compute_kpi_visuals(series_struct, grid_items) do
    compute_kpi_datasets(series_struct, grid_items) |> elem(1)
  end

  defp compute_kpi_datasets(series_struct, grid_items) do
    grid_items
    |> Enum.filter(fn item -> String.downcase(to_string(item["type"] || "kpi")) == "kpi" end)
    |> Enum.reduce({[], []}, fn item, {values, visuals} ->
      case build_kpi_dataset(series_struct, item) do
        nil -> {values, visuals}
        {value_map, nil} -> {[value_map | values], visuals}
        {value_map, visual_map} -> {[value_map | values], [visual_map | visuals]}
      end
    end)
    |> then(fn {vals, vis} -> {Enum.reverse(vals), Enum.reverse(vis)} end)
  end

  defp build_kpi_dataset(series_struct, item) do
    id = to_string(item["id"])
    path = to_string(item["path"] || "")
    func = String.downcase(to_string(item["function"] || "mean"))
    size = to_string(item["size"] || "m")
    subtype = normalize_kpi_subtype(item["subtype"], item)

    case subtype do
      "split" ->
        list = aggregate_for_function(series_struct, path, func, 2) |> List.wrap()
        len = length(list)
        prev = if len >= 2, do: Enum.at(list, len - 2), else: nil
        curr = if len >= 1, do: Enum.at(list, len - 1), else: nil
        current = to_number(curr)
        previous = to_number(prev)
        show_diff = !!item["diff"]
        has_visual = !!item["timeseries"]

        value_map =
          %{
            id: id,
            subtype: "split",
            size: size,
            current: current,
            previous: previous,
            show_diff: show_diff,
            has_visual: has_visual,
            visual_type: if(has_visual, do: "sparkline", else: nil)
          }
          |> Map.put(:path, path)

        visual_map =
          if has_visual do
            %{id: id, type: "sparkline", data: build_kpi_timeline(series_struct, path)}
          end

        {value_map, visual_map}

      "goal" ->
        value =
          aggregate_for_function(series_struct, path, func, 1)
          |> List.wrap()
          |> List.first()
          |> to_number()

        target = to_number(item["goal_target"])

        progress_enabled = !!item["goal_progress"]
        invert_goal = !!item["goal_invert"]

        ratio =
          if is_number(value) and is_number(target) and target != 0, do: value / target, else: nil

        has_visual = progress_enabled and ratio != nil

        value_map =
          %{
            id: id,
            subtype: "goal",
            size: size,
            value: value,
            target: target,
            progress_enabled: progress_enabled,
            progress_ratio: ratio,
            invert: invert_goal,
            has_visual: has_visual,
            visual_type: if(has_visual, do: "progress", else: nil)
          }
          |> Map.put(:path, path)

        visual_map =
          if has_visual do
            %{
              id: id,
              type: "progress",
              current: value || 0.0,
              target: target,
              ratio: ratio,
              invert: invert_goal
            }
          end

        {value_map, visual_map}

      _ ->
        value =
          aggregate_for_function(series_struct, path, func, 1)
          |> List.wrap()
          |> List.first()
          |> to_number()

        has_visual = !!item["timeseries"]

        value_map =
          %{
            id: id,
            subtype: "number",
            size: size,
            value: value,
            has_visual: has_visual,
            visual_type: if(has_visual, do: "sparkline", else: nil)
          }
          |> Map.put(:path, path)

        visual_map =
          if has_visual do
            %{id: id, type: "sparkline", data: build_kpi_timeline(series_struct, path)}
          end

        {value_map, visual_map}
    end
  end

  defp build_kpi_timeline(series_struct, path) do
    normalized_path = to_string(path || "")

    timeline_map =
      format_timeline_map(series_struct, normalized_path, 1, fn at, value ->
        naive = DateTime.to_naive(at)
        utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
        ts = DateTime.to_unix(utc_dt, :millisecond)

        val =
          cond do
            match?(%Decimal{}, value) -> Decimal.to_float(value)
            is_number(value) -> value * 1.0
            true -> 0.0
          end

        [ts, val]
      end)

    extract_timeline_series(timeline_map, normalized_path)
  end

  defp format_timeline_map(series_struct, path, slices, callback) do
    result = Trifle.Stats.Series.format_timeline(series_struct, path, slices, callback)

    cond do
      is_map(result) -> result
      is_list(result) -> %{path => result}
      true -> %{}
    end
  end

  defp extract_timeline_series(timeline_map, path) do
    cond do
      timeline_map == %{} ->
        []

      Map.has_key?(timeline_map, path) ->
        normalize_timeline_points(Map.get(timeline_map, path))

      true ->
        timeline_map
        |> Enum.take(1)
        |> Enum.map(fn {_k, value} -> normalize_timeline_points(value) end)
        |> List.first()
        |> case do
          nil -> []
          points -> points
        end
    end
  end

  defp normalize_timeline_points(nil), do: []
  defp normalize_timeline_points(list) when is_list(list), do: list
  defp normalize_timeline_points(other), do: List.wrap(other)

  defp merge_category_formatted_with_order({acc_map, acc_order}, formatted) do
    cond do
      is_list(formatted) ->
        formatted
        |> Enum.filter(&is_map/1)
        |> Enum.reduce({acc_map, acc_order}, &merge_category_map_with_order(&2, &1))

      is_map(formatted) ->
        merge_category_map_with_order({acc_map, acc_order}, formatted)

      true ->
        {acc_map, acc_order}
    end
  end

  defp merge_category_map_with_order({acc_map, acc_order}, map) do
    Enum.reduce(map, {acc_map, acc_order}, fn {key, value}, {map_acc, order_acc} ->
      name = to_string(key)
      number = normalize_number(value)
      updated_map = Map.update(map_acc, name, number, fn existing -> existing + number end)
      updated_order = if name in order_acc, do: order_acc, else: order_acc ++ [name]
      {updated_map, updated_order}
    end)
  end

  defp category_custom_order?(paths) do
    sanitized =
      paths
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case sanitized do
      [] -> false
      list -> length(list) > 1 and Enum.all?(list, &(not String.contains?(&1, "*")))
    end
  end

  defp sort_category_entries(entries, encounter_order, wildcard_paths?, custom_order?) do
    cond do
      wildcard_paths? ->
        Enum.sort_by(entries, fn %{name: name} -> natural_sort_key(name) end)

      custom_order? and encounter_order != [] ->
        index_map = encounter_order |> Enum.with_index() |> Map.new()
        fallback_index = map_size(index_map)

        Enum.sort_by(entries, fn %{name: name} ->
          {Map.get(index_map, name, fallback_index), natural_sort_key(name)}
        end)

      true ->
        Enum.sort_by(entries, fn %{name: name} -> String.downcase(name || "") end)
    end
  end

  defp natural_sort_key(nil), do: [{:str, ""}]

  defp natural_sort_key(name) when is_binary(name) do
    case Regex.scan(~r/\d+|\D+/, name) do
      [] ->
        [{:str, String.downcase(name)}]

      segments ->
        segments
        |> Enum.map(&List.first/1)
        |> Enum.map(&natural_token/1)
    end
  end

  defp natural_sort_key(other), do: other |> to_string() |> natural_sort_key()

  defp natural_token(segment) do
    cond do
      segment == "" ->
        {:str, ""}

      true ->
        case Integer.parse(segment) do
          {int, ""} ->
            {:num, int}

          _ ->
            case Float.parse(segment) do
              {float, ""} -> {:num, float}
              _ -> {:str, String.downcase(segment)}
            end
        end
    end
  end

  defp aggregate_for_function(series_struct, path, func, slices) do
    case func do
      "sum" -> Trifle.Stats.Series.aggregate_sum(series_struct, path, slices)
      "min" -> Trifle.Stats.Series.aggregate_min(series_struct, path, slices)
      "max" -> Trifle.Stats.Series.aggregate_max(series_struct, path, slices)
      _ -> Trifle.Stats.Series.aggregate_mean(series_struct, path, slices)
    end
  end

  defp to_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_number(v) when is_number(v), do: v * 1.0

  defp to_number(v) when is_binary(v) do
    trimmed = String.trim(v)

    case trimmed do
      "" ->
        nil

      _ ->
        cleaned = String.replace(trimmed, ~r/[,_\s]/, "")

        case Float.parse(cleaned) do
          {num, _} -> num
          :error -> nil
        end
    end
  end

  defp to_number(_), do: nil

  # Build timeseries chart data for timeseries widgets
  defp compute_timeseries_widgets(series_struct, grid_items) do
    items =
      grid_items
      |> Enum.filter(fn item ->
        String.downcase(to_string(item["type"] || "")) == "timeseries"
      end)
      |> Enum.map(fn item ->
        id = to_string(item["id"])

        raw_paths =
          case item["paths"] do
            list when is_list(list) -> list
            _ -> []
          end

        fallback_paths =
          case Map.get(item, "path") do
            nil -> []
            "" -> []
            value -> [value]
          end

        paths =
          (raw_paths ++ fallback_paths)
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        chart_type = String.downcase(to_string(item["chart_type"] || "line"))
        stacked = !!item["stacked"]
        normalized = !!item["normalized"]
        legend = !!item["legend"]
        y_label = to_string(item["y_label"] || "")

        # Use formatter to align timeline and values per path
        timeline_callback = fn at, value ->
          naive = DateTime.to_naive(at)
          utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
          ts = DateTime.to_unix(utc_dt, :millisecond)

          val =
            case value do
              %Decimal{} = d -> Decimal.to_float(d)
              v when is_number(v) -> v * 1.0
              _ -> 0.0
            end

          [ts, val]
        end

        per_path =
          Enum.reduce(paths, [], fn path, acc ->
            timeline_map = format_timeline_map(series_struct, path, 1, timeline_callback)

            Enum.reduce(timeline_map, acc, fn {series_path, data}, inner_acc ->
              name = to_string(series_path)
              normalized_data = normalize_timeline_points(data)

              case Enum.find_index(inner_acc, &(&1.name == name)) do
                nil ->
                  inner_acc ++ [%{name: name, data: normalized_data}]

                idx ->
                  List.update_at(inner_acc, idx, fn _ -> %{name: name, data: normalized_data} end)
              end
            end)
          end)

        series =
          if normalized and length(per_path) > 0 do
            # Build normalized percentages across series
            Enum.map(per_path, fn s ->
              values = s.data

              normed =
                Enum.with_index(values)
                |> Enum.map(fn {point, idx} ->
                  {ts, v} =
                    case point do
                      [ts0, v0] -> {ts0, v0}
                      {ts0, v0} -> {ts0, v0}
                      _ -> {nil, 0.0}
                    end

                  total =
                    Enum.reduce(per_path, 0.0, fn other, acc ->
                      ov =
                        case Enum.at(other.data, idx) do
                          [_, ovv] -> ovv
                          {_, ovv} -> ovv
                          _ -> 0.0
                        end

                      acc + (ov || 0.0)
                    end)

                  pct = if total > 0.0 and is_number(v), do: v / total * 100.0, else: 0.0
                  [ts, pct]
                end)

              %{s | data: normed}
            end)
          else
            per_path
          end

        %{
          id: id,
          chart_type: chart_type,
          stacked: stacked,
          normalized: normalized,
          legend: legend,
          y_label: y_label,
          series: series
        }
      end)

    Logger.debug(fn ->
      summary =
        Enum.map(items, fn i ->
          %{
            id: i.id,
            series: Enum.map(i.series, fn s -> %{name: s.name, points: length(s.data)} end)
          }
        end)

      "Timeseries widgets: " <> inspect(summary)
    end)

    items
  end

  # Build category chart data for category widgets using the formatter
  defp compute_category_widgets(series_struct, grid_items) do
    items =
      grid_items
      |> Enum.filter(fn item -> String.downcase(to_string(item["type"] || "")) == "category" end)
      |> Enum.map(fn item ->
        id = to_string(item["id"])

        raw_paths =
          case item["paths"] do
            list when is_list(list) -> list
            _ -> []
          end

        fallback_paths =
          case Map.get(item, "path") do
            nil -> []
            "" -> []
            value -> [value]
          end

        paths =
          (raw_paths ++ fallback_paths)
          |> Enum.map(&to_string/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        chart_type = String.downcase(to_string(item["chart_type"] || "bar"))

        slice_count =
          series_struct
          |> Map.get(:series, %{})
          |> case do
            series_map when is_map(series_map) ->
              values = Map.get(series_map, :values) || Map.get(series_map, "values") || []
              if is_list(values) and length(values) > 1, do: 2, else: 1

            _ ->
              1
          end

        {merged_map, encounter_order} =
          Enum.reduce(paths, {%{}, []}, fn path, acc ->
            formatted = Trifle.Stats.Series.format_category(series_struct, path, slice_count)
            merge_category_formatted_with_order(acc, formatted)
          end)

        wildcard_paths? = Enum.any?(paths, &String.contains?(&1, "*"))
        custom_order? = category_custom_order?(paths)

        data =
          merged_map
          |> Enum.map(fn {k, v} -> %{name: to_string(k), value: normalize_number(v)} end)
          |> sort_category_entries(encounter_order, wildcard_paths?, custom_order?)

        %{
          id: id,
          chart_type: chart_type,
          data: data
        }
      end)

    Logger.debug(fn ->
      summary = Enum.map(items, fn i -> %{id: i.id, entries: length(i.data)} end)
      "Category widgets: " <> inspect(summary)
    end)

    items
  end

  defp compute_text_widgets(grid_items) do
    grid_items
    |> Enum.filter(fn item -> String.downcase(to_string(item["type"] || "")) == "text" end)
    |> Enum.map(fn item ->
      id = to_string(item["id"])
      subtype = normalize_text_subtype(item["subtype"])
      color = resolve_text_widget_color(item["color"])

      base = %{
        id: id,
        subtype: subtype,
        title: to_string(item["title"] || ""),
        color_id: color.id,
        background_color: color.background,
        text_color: color.text
      }

      case subtype do
        "html" ->
          Map.put(base, :payload, to_string(item["payload"] || ""))

        _ ->
          base
          |> Map.put(:title_size, normalize_text_title_size(item["title_size"]))
          |> Map.put(:alignment, normalize_text_alignment(item["alignment"]))
          |> Map.put(:subtitle, item["subtitle"] |> to_string() |> String.trim())
      end
    end)
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
        widget
        |> compute_timeseries_widgets_for(stats)
        |> maybe_put_chart(base)

      type == "category" ->
        widget
        |> compute_category_widgets_for(stats)
        |> maybe_put_chart(base)

      type == "kpi" ->
        widget
        |> compute_kpi_dataset_for(stats)
        |> maybe_put_kpi_data(base)

      type == "text" ->
        widget
        |> compute_text_widgets_for()
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

  defp compute_kpi_dataset_for(widget, stats) do
    build_kpi_dataset(stats, widget)
  end

  defp compute_timeseries_widgets_for(widget, stats) do
    compute_timeseries_widgets(stats, [widget]) |> List.first()
  end

  defp compute_category_widgets_for(widget, stats) do
    compute_category_widgets(stats, [widget]) |> List.first()
  end

  defp compute_text_widgets_for(widget) do
    compute_text_widgets([widget])
    |> Enum.find(fn item -> item.id == to_string(widget["id"]) end)
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

  defp normalize_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_number(v) when is_number(v), do: v * 1.0
  defp normalize_number(_), do: 0.0

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

  defp dashboard_has_key?(socket) when is_struct(socket, Phoenix.LiveView.Socket) do
    case socket.assigns.dashboard.key do
      nil -> false
      "" -> false
      _key -> true
    end
  end

  defp dashboard_has_key?(assigns) when is_map(assigns) do
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
        |> ExploreLive.format_nested_path(sorted_paths, transponder_info)
        |> HTML.safe_to_string()

      %{"value" => path, "label" => label}
    end)
  end

  defp build_widget_path_options(_assigns), do: []

  defp timeseries_paths_for_form(nil), do: [""]

  defp timeseries_paths_for_form(paths) when is_list(paths) do
    cleaned = Enum.map(paths, &to_string/1)

    case cleaned do
      [] -> [""]
      list -> list
    end
  end

  defp timeseries_paths_for_form(path), do: timeseries_paths_for_form([path])

  attr(:id, :string, required: true)
  attr(:name, :string, required: true)
  attr(:value, :string, default: "")
  attr(:placeholder, :string, default: "")
  attr(:path_options, :list, default: [])

  attr(:input_class, :string,
    default:
      "block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
  )

  defp path_autocomplete_input(assigns) do
    assigns = assign(assigns, :options_json, Jason.encode!(assigns.path_options))

    ~H"""
    <div id={"#{@id}-wrapper"} class="relative" phx-hook="PathAutocomplete" data-paths={@options_json}>
      <input
        id={@id}
        type="text"
        name={@name}
        value={@value}
        placeholder={@placeholder}
        class={@input_class}
        autocomplete="off"
        spellcheck="false"
        data-role="path-input"
      />
      <div
        id={"#{@id}-suggestions"}
        data-role="suggestions"
        phx-update="ignore"
        class="absolute z-20 mt-1 w-full max-h-60 overflow-y-auto rounded-md border border-gray-200 bg-white shadow-lg dark:border-slate-600 dark:bg-slate-800 hidden"
      >
      </div>
    </div>
    """
  end

  defp normalize_timeseries_paths_param(value) do
    value
    |> case do
      nil -> []
      list when is_list(list) -> list
      other -> [other]
    end
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_timeseries_paths_for_edit(paths) do
    cleaned =
      paths
      |> case do
        nil -> []
        list when is_list(list) -> list
        other -> [other]
      end
      |> Enum.map(&to_string/1)

    case cleaned do
      [] -> [""]
      list -> list
    end
  end

  defp normalize_category_paths_param(value), do: normalize_timeseries_paths_param(value)
  defp normalize_category_paths_for_edit(paths), do: normalize_timeseries_paths_for_edit(paths)

  defp category_paths_for_form(%{} = widget) do
    paths = normalize_category_paths_for_edit(widget["paths"])

    has_populated_path =
      paths
      |> Enum.map(&String.trim/1)
      |> Enum.any?(&(&1 != ""))

    cond do
      has_populated_path -> paths
      true -> normalize_category_paths_for_edit(widget["path"])
    end
  end

  defp category_paths_for_form(paths), do: normalize_category_paths_for_edit(paths)

  defp maybe_auto_expand_widget_paths(widget, options) when is_map(widget) do
    type = widget["type"] |> to_string() |> String.downcase()

    case type do
      "timeseries" ->
        paths =
          widget
          |> Map.get("paths", widget["path"])
          |> normalize_timeseries_paths_for_edit()

        expanded = auto_expand_path_wildcards(paths, options)
        Map.put(widget, "paths", expanded)

      "category" ->
        paths =
          widget
          |> Map.get("paths", widget["path"])
          |> normalize_category_paths_for_edit()
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
        socket
        |> assign(:can_edit_dashboard, Organizations.can_edit_dashboard?(dashboard, membership))
        |> assign(:can_clone_dashboard, Organizations.can_clone_dashboard?(dashboard, membership))

      true ->
        socket
        |> assign(:can_edit_dashboard, false)
        |> assign(:can_clone_dashboard, false)
    end
  end

  defp assign_dashboard(socket, dashboard) do
    socket
    |> assign(:dashboard, dashboard)
    |> assign_dashboard_permissions()
    |> assign_segment_state()
  end

  defp assign_segment_state(socket, overrides \\ %{}) do
    dashboard = socket.assigns.dashboard
    raw_segments = dashboard.segments || []
    previous_values = Map.get(socket.assigns, :segment_values, %{})

    overrides = normalize_segment_value_map(overrides)
    previous_values = normalize_segment_value_map(previous_values)

    {segment_values, segments_with_current} =
      compute_segment_state(raw_segments, overrides, previous_values)

    resolved_key = resolve_dashboard_key(dashboard.key, segments_with_current, segment_values)

    socket
    |> assign(:dashboard_segments, segments_with_current)
    |> assign(:segment_values, segment_values)
    |> assign(:resolved_key, resolved_key)
  end

  defp compute_segment_state(segments, overrides, previous_values) do
    segments
    |> Enum.reduce({%{}, []}, fn segment, {values_acc, segments_acc} ->
      name = segment_name(segment)
      type = segment_type(segment)
      available_values = segment_select_values(segment)
      override_present? = Map.has_key?(overrides, name)
      override_value = Map.get(overrides, name)
      previous_present? = Map.has_key?(previous_values, name)
      previous_value = Map.get(previous_values, name)
      default_value = Map.get(segment, "default_value")

      {selected_value, resolved_default} =
        case type do
          "text" ->
            value =
              cond do
                override_present? -> sanitize_text_value(override_value)
                previous_present? -> sanitize_text_value(previous_value)
                not is_nil(default_value) -> sanitize_text_value(default_value)
                true -> ""
              end

            {value, sanitize_text_value(default_value)}

          _ ->
            resolved_default = resolve_default_value(default_value, available_values)

            selected =
              cond do
                override_present? ->
                  value = sanitize_select_value(override_value)

                  if value in available_values or available_values == [] do
                    value
                  else
                    fallback_select_value(
                      previous_present?,
                      previous_value,
                      resolved_default,
                      available_values
                    )
                  end

                previous_present? ->
                  value = sanitize_select_value(previous_value)

                  if value in available_values or available_values == [] do
                    value
                  else
                    fallback_select_value(false, nil, resolved_default, available_values)
                  end

                true ->
                  fallback_select_value(false, nil, resolved_default, available_values)
              end

            {selected, resolved_default}
        end

      updated_segment =
        segment
        |> Map.put("type", type)
        |> Map.put("default_value", resolved_default)
        |> Map.put("current_value", selected_value)

      {Map.put(values_acc, name, selected_value), [updated_segment | segments_acc]}
    end)
    |> then(fn {values, segments_rev} ->
      {values, Enum.reverse(segments_rev)}
    end)
  end

  defp resolve_dashboard_key(nil, _segments, _values), do: nil
  defp resolve_dashboard_key("", _segments, _values), do: ""

  defp resolve_dashboard_key(pattern, segments, values_map) when is_binary(pattern) do
    captures = extract_captures(pattern)

    if captures == [] do
      strip_regex_anchors(pattern)
    else
      values_map = normalize_segment_value_map(values_map)
      ordered_names = Enum.map(segments, &segment_name/1)

      {values, _unused} =
        Enum.reduce(captures, {[], ordered_names}, fn capture, {acc_values, unused_names} ->
          {value, updated_unused} = capture_value_for_segment(capture, values_map, unused_names)
          {[value | acc_values], updated_unused}
        end)

      substituted = substitute_captures(pattern, captures, Enum.reverse(values))
      strip_regex_anchors(substituted)
    end
  end

  defp capture_value_for_segment(%{name: name}, values_map, unused_names) do
    cond do
      name && Map.has_key?(values_map, name) ->
        value = Map.get(values_map, name, "")
        {value, delete_first(unused_names, name)}

      true ->
        case unused_names do
          [next_name | rest] -> {Map.get(values_map, next_name, ""), rest}
          [] -> {"", []}
        end
    end
  end

  defp extract_captures(pattern) do
    Regex.scan(@capture_group_regex, pattern, return: :index)
    |> Enum.map(&hd/1)
    |> Enum.reduce({[], 0}, fn {start, length}, {acc, idx} ->
      match = binary_part(pattern, start, length)

      case classify_capture(match) do
        {:capturing, name} ->
          info = %{index: idx, start: start, length: length, name: name, raw: match}
          {[info | acc], idx + 1}

        :noncapturing ->
          {acc, idx}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp substitute_captures(pattern, captures, values) do
    {iodata, last_index} =
      Enum.zip(captures, values)
      |> Enum.reduce({[], 0}, fn {capture, value}, {parts, cursor} ->
        prefix_length = capture.start - cursor
        prefix = if prefix_length > 0, do: binary_part(pattern, cursor, prefix_length), else: ""

        {[parts | [prefix, value]], capture.start + capture.length}
      end)

    flat_parts = List.flatten(iodata)
    suffix_length = byte_size(pattern) - last_index
    suffix = if suffix_length > 0, do: binary_part(pattern, last_index, suffix_length), else: ""

    [flat_parts, suffix]
    |> IO.iodata_to_binary()
  end

  defp classify_capture(match) do
    inner = inner_capture_content(match)

    cond do
      String.starts_with?(inner, "?<") ->
        name = extract_group_name(inner, 2)
        {:capturing, name}

      String.starts_with?(inner, "?P<") ->
        name = extract_group_name(inner, 3)
        {:capturing, name}

      String.starts_with?(inner, "?") ->
        prefix = String.slice(inner, 1, 2)

        cond do
          prefix in @noncapturing_prefixes ->
            :noncapturing

          String.starts_with?(inner, "?<") ->
            name = extract_group_name(inner, 2)
            {:capturing, name}

          String.starts_with?(inner, "?P<") ->
            name = extract_group_name(inner, 3)
            {:capturing, name}

          true ->
            {:capturing, nil}
        end

      true ->
        {:capturing, nil}
    end
  end

  defp inner_capture_content(capture) do
    capture
    |> String.slice(1, max(byte_size(capture) - 2, 0))
  end

  defp extract_group_name(inner, prefix_length) do
    rest = String.slice(inner, prefix_length, byte_size(inner) - prefix_length)

    case String.split(rest, ">", parts: 2) do
      [name | _] -> String.trim(name)
      _ -> nil
    end
  end

  defp strip_regex_anchors(nil), do: nil

  defp strip_regex_anchors(value) when is_binary(value) do
    value
    |> strip_leading_anchor()
    |> strip_trailing_anchor()
  end

  defp strip_leading_anchor(""), do: ""
  defp strip_leading_anchor("^" <> rest), do: strip_leading_anchor(rest)
  defp strip_leading_anchor(value), do: value

  defp strip_trailing_anchor(""), do: ""

  defp strip_trailing_anchor(value) do
    if String.ends_with?(value, "$") do
      value
      |> String.trim_trailing("$")
      |> strip_trailing_anchor()
    else
      value
    end
  end

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

  defp normalize_segment_value_map(nil), do: %{}

  defp normalize_segment_value_map(values) when is_map(values) do
    values
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized_key = key |> to_string()

      normalized_value =
        cond do
          is_binary(value) -> value
          is_nil(value) -> ""
          true -> to_string(value)
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_segment_value_map(_other), do: %{}

  defp sanitize_select_value(nil), do: ""
  defp sanitize_select_value(value) when is_binary(value), do: value
  defp sanitize_select_value(value), do: to_string(value)

  defp sanitize_text_value(nil), do: ""
  defp sanitize_text_value(value) when is_binary(value), do: value
  defp sanitize_text_value(value), do: to_string(value)

  defp delete_first([], _value), do: []
  defp delete_first([value | rest], value), do: rest
  defp delete_first([head | rest], value), do: [head | delete_first(rest, value)]

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

  defp build_url_params(%Phoenix.LiveView.Socket{} = socket), do: build_url_params(socket.assigns)

  defp build_url_params(data) when is_map(data) do
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
    grid_items = socket.assigns.dashboard.payload["grid"] || []
    {kpi_items, kpi_visuals} = compute_kpi_datasets(result.series, grid_items)
    ts_items = compute_timeseries_widgets(result.series, grid_items)
    cat_items = compute_category_widgets(result.series, grid_items)
    text_items = compute_text_widgets(grid_items)

    {:noreply,
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
     |> maybe_refresh_expanded_widget()
     |> push_event("dashboard_grid_kpi_values", %{items: kpi_items})
     |> push_event("dashboard_grid_kpi_visual", %{items: kpi_visuals})
     |> push_event("dashboard_grid_timeseries", %{items: ts_items})
     |> push_event("dashboard_grid_category", %{items: cat_items})
     |> push_event("dashboard_grid_text", %{items: text_items})}
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
     |> put_flash(:error, "Failed to load dashboard data: #{inspect(error)}")}
  end

  def handle_async(:dashboard_data_task, {:exit, reason}, socket) do
    IO.inspect(reason, label: "Dashboard data fetch failed")
    {:noreply, assign(socket, loading: false)}
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
  defp series_from_assigns(assigns) do
    s = assigns[:stats]

    cond do
      is_map(s) and Map.has_key?(s, :series) -> s.series
      is_map(s) -> s
      true -> nil
    end
  end

  defp csv_escape(v) when is_binary(v) do
    escaped = String.replace(v, "\"", "\"\"")
    "\"" <> escaped <> "\""
  end

  defp csv_escape(nil), do: ""
  defp csv_escape(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp csv_escape(v), do: csv_escape(to_string(v))

  defp dashboard_table_to_csv(assigns) do
    case series_from_assigns(assigns) do
      nil ->
        ""

      series ->
        table = Trifle.Stats.Tabler.tabulize(series)
        at = Enum.reverse(table[:at] || [])
        paths = table[:paths] || []
        values_map = table[:values] || %{}
        header = ["Path" | Enum.map(at, &DateTime.to_iso8601/1)]

        rows =
          Enum.map(paths, fn path ->
            [path | Enum.map(at, fn t -> Map.get(values_map, {path, t}) || 0 end)]
          end)

        [header | rows]
        |> Enum.map(fn cols -> cols |> Enum.map(&csv_escape/1) |> Enum.join(",") end)
        |> Enum.join("\n")
    end
  end

  def handle_event("toggle_export_dropdown", _params, socket) do
    {:noreply,
     assign(socket, :show_export_dropdown, !(socket.assigns[:show_export_dropdown] || false))}
  end

  def handle_event("hide_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, false)}
  end

  def handle_event("download_dashboard_csv", _params, socket) do
    series = series_from_assigns(socket.assigns)

    if is_nil(series) do
      {:noreply, put_flash(socket, :error, "No data to export")}
    else
      csv = dashboard_table_to_csv(socket.assigns)
      fname = export_filename("dashboard", socket.assigns, ".csv")

      {:noreply,
       push_event(socket, "file_download", %{content: csv, filename: fname, type: "text/csv"})}
    end
  end

  def handle_event("download_dashboard_json", _params, socket) do
    series = series_from_assigns(socket.assigns)

    if is_nil(series) do
      {:noreply, put_flash(socket, :error, "No data to export")}
    else
      at = (series[:at] || []) |> Enum.map(&DateTime.to_iso8601/1)
      values = series[:values] || []
      json = Jason.encode!(%{at: at, values: values})
      fname = export_filename("dashboard", socket.assigns, ".json")

      {:noreply,
       push_event(socket, "file_download", %{
         content: json,
         filename: fname,
         type: "application/json"
       })}
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

  def handle_event("segments_editor_change", %{"segments" => segments_params}, socket) do
    current_segments = socket.assigns.configure_segments || []

    updated_segments =
      current_segments
      |> merge_segment_form_params(segments_params)
      |> normalize_configure_segments()

    {:noreply, assign(socket, :configure_segments, updated_segments)}
  end

  def handle_event("segments_editor_change", _params, socket), do: {:noreply, socket}

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
      {:noreply, put_flash(socket, :error, "You do not have permission to update this dashboard")}
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
             |> assign(:breadcrumb_links, updated_breadcrumbs)
             |> assign(:page_title, updated_page_title)
             |> assign(:configure_segments, configure_segments_from_dashboard(updated_dashboard))
             |> put_flash(:info, "Settings saved")}

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
    ~H"""
    <div
      id="dashboard-page-root"
      class="flex flex-col dark:bg-slate-900 min-h-screen relative"
      phx-hook="FileDownload"
    >
      <%= if @print_mode do %>
        <style>
          @media print {
            @page { size: A3; margin: 8mm; }
            /* Force white page background and avoid printing element backgrounds */
            html, body { background: #ffffff !important; -webkit-print-color-adjust: economy !important; print-color-adjust: economy !important; }
            .dark, .dark body { background: #ffffff !important; }
            /* Remove any focus rings, outlines, and shadows that can appear thicker in print */
            *, *::before, *::after { box-shadow: none !important; text-shadow: none !important; outline: none !important; }
            /* Common content containers */
            .grid-stack-item-content { box-shadow: none !important; }
            .container { max-width: 100% !important; width: 100% !important; }
            .grid-stack { max-width: 100% !important; width: 100% !important; }
            #phx-topbar { display: none !important; }
          }
        </style>
      <% end %>
      <!-- Hidden iframe target for downloads to avoid navigating away from LiveView -->
      <iframe
        name="download_iframe"
        style="display:none"
        aria-hidden="true"
        onload="(function(){['dashboard-download-menu','explore-download-menu'].forEach(function(id){var m=document.getElementById(id); if(!m) return; var b=m.querySelector('[data-role=download-button]'); var t=m.querySelector('[data-role=download-text]'); var d=(m.dataset&&m.dataset.defaultLabel)||'Download'; if(b){b.disabled=false; b.classList.remove('opacity-70','cursor-wait');} if(t){t.textContent=d;}})})()"
      >
      </iframe>
      <script>
        window.__downloadPoller = window.__downloadPoller || setInterval(function(){
          try {
            var m = document.cookie.match(/(?:^|; )download_token=([^;]+)/);
            if (m) {
              // Clear cookie and reset UI
              document.cookie = 'download_token=; Max-Age=0; path=/';
              ['dashboard-download-menu','explore-download-menu'].forEach(function(id){
                var menu=document.getElementById(id); if(!menu) return;
                var btn=menu.querySelector('[data-role=download-button]');
                var txt=menu.querySelector('[data-role=download-text]');
                var defaultLabel=(menu.dataset&&menu.dataset.defaultLabel)||'Download';
                if(btn){btn.disabled=false; btn.classList.remove('opacity-70','cursor-wait');}
                if(txt){txt.textContent=defaultLabel;}
              });
            }
          } catch (e) {}
        }, 500);
      </script>
      <!-- Loading Overlay (covers entire page; message at 1/3 height) -->
      <%= if (@loading_chunks && @loading_progress) || @transponding do %>
        <div class="absolute inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 z-50">
          <div class="absolute left-1/2 -translate-x-1/2" style="top: 33%;">
            <div class="flex flex-col items-center space-y-3">
              <div class="flex items-center space-x-2">
                <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 dark:border-slate-600 border-t-teal-500">
                </div>
                <span class="text-sm text-gray-600 dark:text-white">
                  <%= if @transponding do %>
                    Transponding data...
                  <% else %>
                    Scientificating piece {@loading_progress.current} of {@loading_progress.total}...
                  <% end %>
                </span>
              </div>
              <!-- Always reserve space for progress bar to keep text position consistent -->
              <div class="w-64 h-2">
                <%= if @loading_chunks && @loading_progress do %>
                  <div class="w-full bg-gray-200 dark:bg-slate-600 rounded-full h-2">
                    <div
                      class="bg-teal-500 h-2 rounded-full transition-all duration-300"
                      style={"width: #{(@loading_progress.current / @loading_progress.total * 100)}%"}
                    >
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      <main class="flex-1 w-full">
        <!-- Header -->
        <div class={if(@is_public_access, do: "mb-2", else: "mb-6")}>
          <div class="flex items-center justify-between">
            <!-- Left: Title only -->
            <div class="min-w-0">
              <h1 class="text-2xl font-bold text-gray-900 dark:text-white truncate">
                {@dashboard.name}
              </h1>
            </div>

            <%= if !@print_mode && !@is_public_access && @current_user && @can_edit_dashboard do %>
              <!-- Dashboard owner controls -->
              <div class="flex items-center justify-end gap-3 md:gap-4 flex-nowrap w-auto">
                <% add_btn_id = "dashboard-" <> @dashboard.id <> "-add-widget" %>
                <!-- Add Widget Button -->
                <button
                  id={add_btn_id}
                  type="button"
                  class="inline-flex items-center whitespace-nowrap rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                  title="Add widget"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                    class="-ml-0.5 md:mr-1.5 h-4 w-4"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M12 3.75a.75.75 0 01.75.75v6.75h6.75a.75.75 0 010 1.5H12.75v6.75a.75.75 0 01-1.5 0V12.75H4.5a.75.75 0 010-1.5h6.75V4.5a.75.75 0 01.75-.75z"
                      clip-rule="evenodd"
                    />
                  </svg>
                  <span class="hidden md:inline">Add Widget</span>
                </button>
                <!-- Edit Button -->
                <%= if @live_action == :edit do %>
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                  >
                    <svg
                      class="-ml-0.5 mr-1.5 h-4 w-4"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                    >
                      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                    </svg>
                    Cancel
                  </button>
                <% else %>
                  <.link
                    patch={~p"/dashboards/#{@dashboard.id}/edit"}
                    class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                  >
                    <svg
                      class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10"
                      />
                    </svg>
                    <span class="hidden md:inline">Edit</span>
                  </.link>
                  
    <!-- Configure Button -->
                  <.link
                    patch={~p"/dashboards/#{@dashboard.id}/configure"}
                    class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                  >
                    <svg
                      class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                      stroke-width="1.5"
                      stroke="currentColor"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"
                      />
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                      />
                    </svg>
                    <span class="hidden md:inline">Configure</span>
                  </.link>
                <% end %>
                
    <!-- Status Icon Badges -->
                <div id="status-badges" class="flex items-center gap-2" phx-hook="FastTooltip">
                  <!-- Public link -->
                  <%= if @dashboard.access_token do %>
                    <!-- Hidden element with the URL to copy -->
                    <span id="dashboard-public-url" class="hidden">
                      {url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}")}
                    </span>
                    
    <!-- Has token: white/plain button with visual feedback - hidden on XS screens -->
                    <button
                      type="button"
                      phx-click={
                        JS.dispatch("phx:copy", to: "#dashboard-public-url")
                        |> JS.hide(to: "#header-link-icon")
                        |> JS.show(to: "#header-check-icon")
                        |> JS.hide(to: "#header-check-icon", transition: {"", "", ""}, time: 2000)
                        |> JS.show(to: "#header-link-icon", transition: {"", "", ""}, time: 2000)
                      }
                      class="cursor-pointer hidden sm:inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-xs font-medium text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                      data-tooltip="Copy public dashboard link"
                    >
                      <!-- Link Icon (default) -->
                      <svg
                        id="header-link-icon"
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
                          d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z"
                        />
                      </svg>
                      
    <!-- Check Icon (shown temporarily when copied) -->
                      <svg
                        id="header-check-icon"
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-green-600 hidden"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                        />
                      </svg>
                    </button>
                  <% else %>
                    <!-- No token: icon-only (no wrapper), hidden on XS -->
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="No public link available"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-gray-400 dark:text-slate-500"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z"
                        />
                      </svg>
                    </div>
                  <% end %>
                  
    <!-- Visibility badge -->
                  <%= if @dashboard.visibility do %>
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="Visible to everyone in organization"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-teal-600 dark:text-teal-400"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"
                        />
                      </svg>
                    </div>
                  <% else %>
                    <div
                      class="hidden sm:inline-flex items-center justify-center rounded-md px-3 py-2"
                      data-tooltip="Private - only you can see this"
                    >
                      <svg
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        class="h-5 w-5 text-gray-400 dark:text-slate-500"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z"
                        />
                      </svg>
                    </div>
                  <% end %>
                </div>
              </div>
            <% else %>
              <!-- Non-owner or public access view -->
              <%= if !@is_public_access do %>
                <div class="flex items-center gap-2 w-64 justify-end">
                  <span class={[
                    "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium",
                    if(@dashboard.visibility,
                      do:
                        "bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-200 ring-1 ring-inset ring-blue-600/20 dark:ring-blue-500/30",
                      else:
                        "bg-gray-50 dark:bg-gray-900 text-gray-700 dark:text-gray-200 ring-1 ring-inset ring-gray-600/20 dark:ring-gray-500/30"
                    )
                  ]}>
                    {Trifle.Organizations.Dashboard.visibility_display(@dashboard.visibility)}
                  </span>
                </div>
              <% else %>
                <div class="w-64"></div>
              <% end %>
            <% end %>
          </div>
        </div>
        
    <!-- Filter Bar (only show if dashboard has a key) -->
        <%= if dashboard_has_key?(assigns) do %>
          <.live_component
            module={TrifleApp.Components.FilterBar}
            id="dashboard_filter_bar"
            config={@database_config}
            from={@from}
            to={@to}
            granularity={@granularity}
            smart_timeframe_input={@smart_timeframe_input}
            use_fixed_display={@use_fixed_display}
            available_granularities={@available_granularities}
            show_controls={!@print_mode}
            show_timeframe_dropdown={false}
            show_granularity_dropdown={false}
            sources={@sources || []}
            selected_source={@selected_source_ref}
            source_locked={true}
            force_granularity_dropdown={@print_mode}
          />
        <% end %>
        <% segment_definitions = @dashboard_segments || [] %>
        <%= if !@print_mode and segment_definitions != [] do %>
          <form
            id="dashboard-segments-form"
            class="mb-6 flex justify-center"
            phx-change="update_segment_filters"
            phx-submit="update_segment_filters"
          >
            <div class="flex flex-wrap items-center justify-center gap-4">
              <%= for segment <- segment_definitions do %>
                <% segment_name = segment["name"] %>
                <% label = segment["label"] || segment_name || "Segment" %>
                <% current_value = Map.get(@segment_values || %{}, segment_name, "") %>
                <label class="flex items-center gap-2 text-sm font-medium text-gray-700 dark:text-slate-300">
                  <span>{label}:</span>
                  <%= if segment["type"] == "text" do %>
                    <input
                      type="text"
                      name={"segments[#{segment_name}]"}
                      value={current_value}
                      placeholder={segment["placeholder"] || ""}
                      phx-debounce="500"
                      class="w-56 rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                    />
                  <% else %>
                    <% groups = segment["groups"] || [] %>
                    <% has_items = Enum.any?(groups, fn group -> (group["items"] || []) != [] end) %>
                    <div class="grid grid-cols-1">
                      <select
                        name={"segments[#{segment_name}]"}
                        class="col-start-1 row-start-1 w-56 appearance-none rounded-md border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm py-1.5 pr-8 pl-3"
                      >
                        <%= for group <- groups do %>
                          <% group_label = group["label"] %>
                          <%= if group_label && group_label != "" do %>
                            <optgroup label={group_label}>
                              <%= for item <- group["items"] || [] do %>
                                <% option_value = item["value"] || "" %>
                                <option value={option_value} selected={option_value == current_value}>
                                  {item["label"] || option_value}
                                </option>
                              <% end %>
                            </optgroup>
                          <% else %>
                            <%= for item <- group["items"] || [] do %>
                              <% option_value = item["value"] || "" %>
                              <option value={option_value} selected={option_value == current_value}>
                                {item["label"] || option_value}
                              </option>
                            <% end %>
                          <% end %>
                        <% end %>
                        <%= if !has_items do %>
                          <option value="" selected={current_value in [nil, ""]} disabled>
                            No options configured
                          </option>
                        <% end %>
                      </select>
                      <svg
                        viewBox="0 0 16 16"
                        fill="currentColor"
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
                  <% end %>
                </label>
              <% end %>
            </div>
          </form>
        <% end %>
        
    <!-- Edit Form (only shown in edit mode for authenticated users) -->
        <%= if !@is_public_access && @live_action == :edit && @dashboard_form do %>
          <div class="mb-6">
            <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-6">
              <h2 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Edit Dashboard</h2>

              <.form for={@dashboard_form} phx-submit="save_dashboard" class="space-y-4">
                <div>
                  <label
                    for="dashboard_payload"
                    class="block text-sm font-medium text-gray-700 dark:text-slate-300"
                  >
                    Payload
                  </label>
                  <textarea
                    name="dashboard[payload]"
                    id="dashboard_payload"
                    rows="10"
                    class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm font-mono"
                    placeholder="JSON configuration for dashboard visualization"
                  ><%= if @dashboard.payload, do: Jason.encode!(@dashboard.payload, pretty: true), else: "" %></textarea>
                  <%= if @dashboard_changeset && @dashboard_changeset.errors[:payload] do %>
                    <p class="mt-1 text-sm text-red-600 dark:text-red-400">
                      {case @dashboard_changeset.errors[:payload] do
                        [{message, _}] -> message
                        [{message, _} | _] -> message
                        message when is_binary(message) -> message
                        _ -> "Invalid payload format"
                      end}
                    </p>
                  <% end %>
                  <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                    Enter valid JSON configuration for the dashboard visualization
                  </p>
                </div>

                <div class="flex items-center justify-end gap-3 pt-4">
                  <button
                    type="button"
                    phx-click="cancel_edit"
                    class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                  >
                    Save Changes
                  </button>
                </div>
              </.form>
            </div>
          </div>
        <% end %>

        <% raw_grid_items = (@dashboard.payload || %{})["grid"] %>
        <% grid_items = if is_list(raw_grid_items), do: raw_grid_items, else: [] %>
        <% has_grid_items = grid_items != [] %>
        <% text_items = compute_text_widgets(grid_items) %>
        
    <!-- Grid Layout -->
        <div class={[
          "mb-6",
          if(has_grid_items, do: nil, else: "hidden")
        ]}>
          <div
            id="dashboard-grid"
            class="grid-stack"
            phx-update="ignore"
            phx-hook="DashboardGrid"
            data-print-mode={if @print_mode, do: "true", else: "false"}
            data-editable={
              if !@is_public_access && @current_user && @can_edit_dashboard,
                do: "true",
                else: "false"
            }
            data-cols="12"
            data-min-rows="8"
            data-add-btn-id={"dashboard-" <> @dashboard.id <> "-add-widget"}
            data-colors={ChartColors.json_palette()}
            data-initial-grid={Jason.encode!(grid_items)}
            data-initial-text={Jason.encode!(text_items)}
            data-dashboard-id={@dashboard.id}
            data-public-token={@public_token}
          >
          </div>
        </div>
        
    <!-- Configure Modal -->
        <%= if !@is_public_access && @live_action == :configure do %>
          <.app_modal
            id="configure-modal"
            show={true}
            on_cancel={JS.patch(~p"/dashboards/#{@dashboard.id}")}
          >
            <:title>Configure Dashboard</:title>
            <:body>
              <div class="space-y-6">
                <.form
                  for={%{}}
                  phx-change="segments_editor_change"
                  phx-submit="save_settings"
                  class="space-y-6"
                >
                  <!-- Dashboard Name -->
                  <div>
                    <label
                      for="configure_name"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Dashboard Name
                    </label>
                    <input
                      type="text"
                      id="configure_name"
                      name="name"
                      value={@temp_name || @dashboard.name}
                      phx-keyup="update_temp_name"
                      class="w-full block rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                      placeholder="Dashboard name"
                    />
                  </div>
                  
    <!-- Source (editable) -->
                  <div>
                    <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
                      Source
                    </label>
                    <% grouped_sources = group_sources_for_select(@sources || []) %>
                    <div class="grid grid-cols-1 sm:max-w-xs">
                      <select
                        name="source_ref"
                        class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                        disabled={grouped_sources == []}
                      >
                        <%= for {group_label, sources} <- grouped_sources do %>
                          <optgroup label={group_label}>
                            <%= for source <- sources do %>
                              <% value = source_option_value(source) %>
                              <option
                                value={value}
                                selected={source_selected?(@selected_source_ref, source)}
                              >
                                {Source.display_name(source)}
                              </option>
                            <% end %>
                          </optgroup>
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
                    <%= if grouped_sources == [] do %>
                      <p class="mt-2 text-xs text-red-600 dark:text-red-400">
                        No available sources. Create a database or project first.
                      </p>
                    <% end %>
                  </div>
                  
    <!-- Dashboard Key -->
                  <div>
                    <label
                      for="configure_key"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Key
                    </label>
                    <input
                      type="text"
                      id="configure_key"
                      name="key"
                      value={@dashboard.key || ""}
                      class="w-full block rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                      placeholder="e.g., sales.metrics"
                      required
                    />
                    <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                      Use regex capture groups to mark dynamic segments, for example <code>commodity::events::detail::(?&lt;source&gt;.*)</code>. The capture name should match the
                      segment name; otherwise segments fallback to positional order.
                    </p>
                  </div>

                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                    <div class="mb-4">
                      <h3 class="text-sm font-semibold text-gray-900 dark:text-white">
                        Key Segments
                      </h3>
                      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                        Configure dynamic parts of the dashboard key. Each segment becomes a filter exposed at the top of the dashboard.
                      </p>
                    </div>
                    <% configure_segments = @configure_segments || [] %>
                    <div class="space-y-6">
                      <%= for segment <- configure_segments do %>
                        <% segment_id = segment["id"] %>
                        <% segment_name = segment["name"] || "" %>
                        <% segment_label = segment["label"] || "" %>
                        <% segment_type = segment["type"] || "select" %>
                        <% placeholder = segment["placeholder"] || "" %>
                        <% default_value = segment["default_value"] || "" %>
                        <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-gray-50 dark:bg-slate-900/40 p-4 space-y-4">
                          <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-4">
                            <div class="grid grid-cols-1 md:grid-cols-3 gap-4 w-full">
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Name
                                </label>
                                <input
                                  type="text"
                                  required
                                  name={"segments[#{segment_id}][name]"}
                                  value={segment_name}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="source"
                                />
                                <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                                  Matching placeholder name used in the key (e.g. (source)).
                                </p>
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Label
                                </label>
                                <input
                                  type="text"
                                  name={"segments[#{segment_id}][label]"}
                                  value={segment_label}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="Source"
                                />
                                <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                                  Display name shown above the dashboard.
                                </p>
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Segment Type
                                </label>
                                <div class="grid grid-cols-1">
                                  <select
                                    name={"segments[#{segment_id}][type]"}
                                    class="col-start-1 row-start-1 block w-full appearance-none rounded-md border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm py-1.5 pr-8 pl-3"
                                  >
                                    <option value="select" selected={segment_type != "text"}>
                                      Dropdown
                                    </option>
                                    <option value="text" selected={segment_type == "text"}>
                                      Text input
                                    </option>
                                  </select>
                                  <svg
                                    viewBox="0 0 16 16"
                                    fill="currentColor"
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
                            </div>
                            <button
                              type="button"
                              phx-click="segments_remove"
                              phx-value-id={segment_id}
                              class="inline-flex items-center gap-1 rounded-md bg-transparent px-3 py-2 text-xs font-medium text-red-600 hover:bg-red-500/10 dark:text-red-400"
                            >
                              <svg
                                xmlns="http://www.w3.org/2000/svg"
                                viewBox="0 0 20 20"
                                fill="currentColor"
                                class="h-4 w-4"
                              >
                                <path
                                  fill-rule="evenodd"
                                  d="M6.28 5.22a.75.75 0 0 1 1.06 0L10 7.94l2.66-2.72a.75.75 0 0 1 1.08 1.04L11.06 9l2.72 2.66a.75.75 0 1 1-1.04 1.08L10 10.06l-2.66 2.72a.75.75 0 1 1-1.08-1.04L8.94 9l-2.72-2.66a.75.75 0 0 1 0-1.06Z"
                                  clip-rule="evenodd"
                                />
                              </svg>
                              Remove
                            </button>
                          </div>

                          <%= if segment_type == "text" do %>
                            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Placeholder
                                </label>
                                <input
                                  type="text"
                                  name={"segments[#{segment_id}][placeholder]"}
                                  value={placeholder}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="e.g., Enter product ID"
                                />
                              </div>
                              <div>
                                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                  Default value
                                </label>
                                <input
                                  type="text"
                                  name={"segments[#{segment_id}][default_value]"}
                                  value={default_value}
                                  class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                  placeholder="Leave blank for no default"
                                />
                              </div>
                            </div>
                          <% else %>
                            <% groups = segment["groups"] || [] %>
                            <div class="space-y-4">
                              <%= for group <- groups do %>
                                <% group_id = group["id"] %>
                                <% group_label = group["label"] || "" %>
                                <% items = group["items"] || [] %>
                                <div class="rounded-md border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4 space-y-3">
                                  <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                                    <div class="w-full">
                                      <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                                        Group label
                                      </label>
                                      <input
                                        type="text"
                                        name={"segments[#{segment_id}][groups][#{group_id}][label]"}
                                        value={group_label}
                                        class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                        placeholder="Optional label"
                                      />
                                    </div>
                                    <button
                                      type="button"
                                      phx-click="segments_remove_group"
                                      phx-value-segment-id={segment_id}
                                      phx-value-group-id={group_id}
                                      class="inline-flex items-center gap-1 rounded-md bg-transparent px-3 py-2 text-xs font-medium text-red-600 hover:bg-red-500/10 dark:text-red-400"
                                    >
                                      <svg
                                        xmlns="http://www.w3.org/2000/svg"
                                        viewBox="0 0 20 20"
                                        fill="currentColor"
                                        class="h-4 w-4"
                                      >
                                        <path
                                          fill-rule="evenodd"
                                          d="M6.28 5.22a.75.75 0 0 1 1.06 0L10 7.94l2.66-2.72a.75.75 0 0 1 1.08 1.04L11.06 9l2.72 2.66a.75.75 0 1 1-1.04 1.08L10 10.06l-2.66 2.72a.75.75 0 1 1-1.08-1.04L8.94 9l-2.72-2.66a.75.75 0 0 1 0-1.06Z"
                                          clip-rule="evenodd"
                                        />
                                      </svg>
                                      Remove group
                                    </button>
                                  </div>
                                  <div class="space-y-3">
                                    <%= for item <- items do %>
                                      <% item_id = item["id"] %>
                                      <% item_label = item["label"] || "" %>
                                      <% item_value = item["value"] || "" %>
                                      <div class="grid grid-cols-1 md:grid-cols-[auto,1fr,1fr,auto] gap-3 md:items-center">
                                        <div class="flex items-center gap-2">
                                          <input
                                            type="radio"
                                            name={"segments[#{segment_id}][default_value]"}
                                            value={item_value}
                                            checked={item_value == default_value}
                                            class="h-4 w-4 text-teal-600 focus:ring-teal-500"
                                          />
                                          <span class="text-xs text-gray-500 dark:text-slate-400">
                                            Default
                                          </span>
                                        </div>
                                        <div>
                                          <label class="sr-only">Option label</label>
                                          <input
                                            type="text"
                                            name={"segments[#{segment_id}][groups][#{group_id}][items][#{item_id}][label]"}
                                            value={item_label}
                                            class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                            placeholder="Label"
                                          />
                                        </div>
                                        <div>
                                          <label class="sr-only">Option value</label>
                                          <input
                                            type="text"
                                            name={"segments[#{segment_id}][groups][#{group_id}][items][#{item_id}][value]"}
                                            value={item_value}
                                            class="block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                                            placeholder="Value"
                                          />
                                        </div>
                                        <button
                                          type="button"
                                          phx-click="segments_remove_item"
                                          phx-value-segment-id={segment_id}
                                          phx-value-group-id={group_id}
                                          phx-value-item-id={item_id}
                                          class="inline-flex items-center justify-center rounded-md bg-transparent px-2 py-2 text-xs font-medium text-red-600 hover:bg-red-500/10 dark:text-red-400"
                                          aria-label="Remove option"
                                        >
                                          &times;
                                        </button>
                                      </div>
                                    <% end %>
                                  </div>
                                  <button
                                    type="button"
                                    phx-click="segments_add_item"
                                    phx-value-segment-id={segment_id}
                                    phx-value-group-id={group_id}
                                    class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                                  >
                                    <span aria-hidden="true">+</span> Add option
                                  </button>
                                </div>
                              <% end %>
                              <button
                                type="button"
                                phx-click="segments_add_group"
                                phx-value-segment-id={segment_id}
                                class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                              >
                                <span aria-hidden="true">+</span> Add group
                              </button>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                    <div>
                      <button
                        type="button"
                        phx-click="segments_add"
                        class="inline-flex items-center gap-1 rounded-md bg-teal-600 px-3 py-2 text-xs font-semibold text-white shadow-sm hover:bg-teal-500"
                      >
                        <span aria-hidden="true">+</span> Add segment
                      </button>
                    </div>
                  </div>
                  
    <!-- Defaults -->
                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                    <div class="mb-4">
                      <h3 class="text-sm font-semibold text-gray-900 dark:text-white">Defaults</h3>
                      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                        These values are used as the initial timeframe and granularity when opening this dashboard.
                        Timeframe accepts smart inputs like 24h, 2d, 1w, 1mo. You can override database defaults here.
                      </p>
                    </div>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                          Timeframe
                        </label>
                        <input
                          type="text"
                          name="timeframe"
                          value={@dashboard.default_timeframe || @database.default_timeframe || "24h"}
                          class="mt-2 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                          placeholder="e.g. 24h, 2d, 1w, 1mo, 1y"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                          Granularity
                        </label>
                        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                          <select
                            name="granularity"
                            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                          >
                            <%= for g <- @available_granularities do %>
                              <option
                                value={g}
                                selected={
                                  g ==
                                    (@dashboard.default_granularity || @database.default_granularity ||
                                       "1h")
                                }
                              >
                                {g}
                              </option>
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
                      <div class="sm:col-span-2 flex justify-end">
                        <button
                          type="submit"
                          class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                        >
                          Save
                        </button>
                      </div>
                    </div>
                  </div>
                </.form>
                <!-- Actions -->
                <%= if @can_clone_dashboard do %>
                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                    <div class="flex items-center justify-between mb-2">
                      <div>
                        <span class="text-sm font-medium text-gray-700 dark:text-slate-300">
                          Actions
                        </span>
                        <p class="text-xs text-gray-500 dark:text-slate-400">
                          Make a copy of this dashboard.
                        </p>
                      </div>
                      <button
                        type="button"
                        phx-click="duplicate_dashboard"
                        class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                        title="Duplicate dashboard"
                      >
                        <svg
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                          class="md:-ml-0.5 md:mr-1.5 h-4 w-4"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75"
                          />
                        </svg>
                        <span class="hidden md:inline">Duplicate</span>
                      </button>
                    </div>
                  </div>
                <% end %>

                <%= if @can_edit_dashboard do %>
                  <!-- Visibility Toggle (moved below Actions) -->
                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6 flex items-center justify-between">
                    <div>
                      <span class="text-sm font-medium text-gray-700 dark:text-slate-300">
                        Visibility
                      </span>
                      <p class="text-xs text-gray-500 dark:text-slate-400">
                        Make this dashboard visible to everyone in the organization
                      </p>
                    </div>
                    <button
                      type="button"
                      phx-click="toggle_visibility"
                      class={[
                        "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-teal-600 focus:ring-offset-2",
                        if(@dashboard.visibility,
                          do: "bg-teal-600",
                          else: "bg-gray-200 dark:bg-gray-700"
                        )
                      ]}
                    >
                      <span class={[
                        "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                        if(@dashboard.visibility, do: "translate-x-5", else: "translate-x-0")
                      ]}>
                      </span>
                    </button>
                  </div>
                  
    <!-- Public Link Management -->
                  <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                    <div class="flex items-center justify-between mb-4">
                      <div>
                        <span class="text-sm font-medium text-gray-700 dark:text-slate-300">
                          Public Link
                        </span>
                        <p class="text-xs text-gray-500 dark:text-slate-400">
                          Allow unauthenticated Read-only access to this dashboard
                        </p>
                      </div>
                    </div>

                    <%= if @dashboard.access_token do %>
                      <!-- Hidden element with the URL to copy -->
                      <span id="modal-dashboard-public-url" class="hidden">
                        {url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}")}
                      </span>

                      <div class="flex items-center gap-3">
                        <!-- Copy Link Button -->
                        <span
                          id="modal-copy-dashboard-link"
                          x-data="{ copied: false }"
                          phx-click={JS.dispatch("phx:copy", to: "#modal-dashboard-public-url")}
                          x-on:click="copied = true; setTimeout(() => copied = false, 3000)"
                          class="flex-1 cursor-pointer inline-flex items-center justify-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-medium text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                          title="Copy public link to clipboard"
                          phx-update="ignore"
                        >
                          <!-- Copy Icon (show when not copied) -->
                          <svg
                            x-show="!copied"
                            class="-ml-0.5 mr-2 h-4 w-4"
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d="M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9a.75.75 0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 0 1 1.927-.184"
                            />
                          </svg>
                          
    <!-- Check Icon (show when copied) -->
                          <svg
                            x-show="copied"
                            class="-ml-0.5 mr-2 h-4 w-4 text-green-600"
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                            />
                          </svg>
                          
    <!-- Text -->
                          <span x-show="!copied">Copy Public Link</span>
                          <span x-show="copied" class="text-green-600">Copied!</span>
                        </span>
                        
    <!-- Remove Button -->
                        <button
                          type="button"
                          phx-click="remove_public_token"
                          data-confirm="Are you sure you want to remove the public link? Anyone with the current link will lose access."
                          class="inline-flex items-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                          title="Remove public link"
                        >
                          <svg
                            class="-ml-0.5 mr-2 h-4 w-4"
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                            />
                          </svg>
                          Remove Link
                        </button>
                      </div>
                    <% else %>
                      <!-- No token: show generate -->
                      <button
                        type="button"
                        phx-click="generate_public_token"
                        class="w-full inline-flex items-center justify-center rounded-md bg-teal-50 dark:bg-teal-900 px-3 py-2 text-sm font-medium text-teal-700 dark:text-teal-200 ring-1 ring-inset ring-teal-600/20 dark:ring-teal-500/30 hover:bg-teal-100 dark:hover:bg-teal-800"
                        title="Generate public link for unauthenticated access"
                      >
                        <svg
                          class="-ml-0.5 mr-2 h-4 w-4"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244"
                          />
                        </svg>
                        Generate Public Link
                      </button>
                    <% end %>
                  </div>
                  
    <!-- Danger Zone -->
                  <div class="border-t border-red-200 dark:border-red-800 pt-6">
                    <div class="mb-4">
                      <span class="text-sm font-medium text-red-700 dark:text-red-400">
                        Danger Zone
                      </span>
                      <p class="text-xs text-red-600 dark:text-red-400">
                        This action cannot be undone
                      </p>
                    </div>

                    <button
                      type="button"
                      phx-click="delete_dashboard"
                      data-confirm="Are you sure you want to delete this dashboard? This action cannot be undone."
                      class="w-full inline-flex items-center justify-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                      title="Delete this dashboard"
                    >
                      <svg
                        class="-ml-0.5 mr-2 h-4 w-4"
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                        />
                      </svg>
                      Delete Dashboard
                    </button>
                  </div>
                <% end %>
              </div>
            </:body>
          </.app_modal>
        <% end %>
        
    <!-- Widget Edit Modal -->
        <%= if !@is_public_access && @editing_widget do %>
          <.app_modal id="widget-modal" show={true} on_cancel={JS.push("close_widget_editor")}>
            <:title>Edit Widget</:title>
            <:body>
              <div class="space-y-6">
                <!-- Widget Type (change updates the modal content) -->
                <.form for={%{}} phx-change="change_widget_type" class="space-y-3">
                  <input type="hidden" name="widget_id" value={@editing_widget["id"]} />
                  <div>
                    <label
                      for="widget_type"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Widget Type
                    </label>
                    <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                      <select
                        id="widget_type"
                        name="widget_type"
                        class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                      >
                        <% sel = @editing_widget["type"] || "kpi" %>
                        <option value="kpi" selected={sel == "kpi"}>KPI</option>
                        <option value="timeseries" selected={sel == "timeseries"}>Timeseries</option>
                        <option value="category" selected={sel == "category"}>Category</option>
                        <option value="text" selected={sel == "text"}>Text</option>
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
                </.form>
                
    <!-- Widget Title and Options -->
                <.form for={%{}} phx-submit="save_widget" class="space-y-4">
                  <input type="hidden" name="widget_id" value={@editing_widget["id"]} />
                  <input type="hidden" name="widget_type" value={@editing_widget["type"] || "kpi"} />
                  <div>
                    <label
                      for="widget_title"
                      class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2"
                    >
                      Title
                    </label>
                    <input
                      type="text"
                      id="widget_title"
                      name="widget_title"
                      value={@editing_widget["title"] || ""}
                      class="flex-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                      placeholder="Widget title"
                    />
                  </div>

                  <%= case (@editing_widget["type"] || "kpi") do %>
                    <% "kpi" -> %>
                      <% subtype = normalize_kpi_subtype(@editing_widget["subtype"], @editing_widget) %>
                      <% fnv = @editing_widget["function"] || "mean" %>
                      <% fnv = if fnv == "avg", do: "mean", else: fnv %>
                      <% sz = @editing_widget["size"] || "m" %>
                      <% diff_checked = !!@editing_widget["diff"] %>
                      <% timeseries_checked = !!@editing_widget["timeseries"] %>
                      <% goal_progress_checked = !!@editing_widget["goal_progress"] %>
                      <% goal_invert_checked = !!@editing_widget["goal_invert"] %>
                      <input type="hidden" name="kpi_subtype" value={subtype} />
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div class="sm:col-span-2">
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            Path
                          </label>
                          <.path_autocomplete_input
                            id="widget-kpi-path"
                            name="kpi_path"
                            value={@editing_widget["path"] || ""}
                            placeholder="e.g. sales.total"
                            path_options={@widget_path_options}
                          />
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            Function
                          </label>
                          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                            <select
                              name="kpi_function"
                              class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                            >
                              <option value="max" selected={fnv == "max"}>max</option>
                              <option value="min" selected={fnv == "min"}>min</option>
                              <option value="mean" selected={fnv == "mean"}>mean</option>
                              <option value="sum" selected={fnv == "sum"}>sum</option>
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
                            Size
                          </label>
                          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                            <select
                              name="kpi_size"
                              class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                            >
                              <option value="s" selected={sz == "s"}>Small</option>
                              <option value="m" selected={sz == "m"}>Medium</option>
                              <option value="l" selected={sz == "l"}>Large</option>
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
                          <label
                            for="kpi_subtype"
                            class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1"
                          >
                            KPI Type
                          </label>
                          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                            <select
                              id="kpi_subtype"
                              name="kpi_subtype"
                              class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                              phx-change="change_kpi_subtype"
                              phx-value-widget-id={@editing_widget["id"]}
                            >
                              <option value="number" selected={subtype == "number"}>Number</option>
                              <option value="split" selected={subtype == "split"}>Split</option>
                              <option value="goal" selected={subtype == "goal"}>Goal</option>
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
                        <%= if subtype == "goal" do %>
                          <div class="sm:col-span-2">
                            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                              Target value
                            </label>
                            <input
                              type="text"
                              name="kpi_goal_target"
                              value={@editing_widget["goal_target"] || ""}
                              class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                              placeholder="e.g. 1200"
                            />
                          </div>
                        <% end %>
                      </div>
                      <%= case subtype do %>
                        <% "split" -> %>
                          <div class="space-y-2">
                            <p class="text-sm text-gray-700 dark:text-slate-300">
                              Split timeframe by half is enabled for this subtype.
                            </p>
                            <div class="flex flex-wrap items-center gap-4">
                              <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                                <input type="checkbox" name="kpi_diff" checked={diff_checked} />
                                Difference between splits
                              </label>
                              <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                                <input
                                  type="checkbox"
                                  name="kpi_timeseries"
                                  checked={timeseries_checked}
                                /> Show timeseries
                              </label>
                            </div>
                            <p class="text-xs text-gray-500 dark:text-slate-400">
                              Shows percent change between halves: (Now − Prev) / |Prev| × 100. Hidden when Prev is missing or zero.
                            </p>
                          </div>
                        <% "goal" -> %>
                          <div class="space-y-2">
                            <div class="flex flex-wrap items-center gap-4">
                              <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                                <input
                                  type="checkbox"
                                  name="kpi_goal_progress"
                                  checked={goal_progress_checked}
                                /> Show progress bar
                              </label>
                              <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                                <input
                                  type="checkbox"
                                  name="kpi_goal_invert"
                                  checked={goal_invert_checked}
                                /> Invert goal (lower is better)
                              </label>
                            </div>
                            <p class="text-xs text-gray-500 dark:text-slate-400">
                              Progress bar illustrates progress toward the target.
                            </p>
                            <p class="text-xs text-gray-500 dark:text-slate-400">
                              When inverted, staying at or below the target is considered success; exceeding it turns the progress indicator red.
                            </p>
                          </div>
                        <% _ -> %>
                          <div class="flex items-center gap-4">
                            <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                              <input
                                type="checkbox"
                                name="kpi_timeseries"
                                checked={timeseries_checked}
                              /> Show timeseries
                            </label>
                          </div>
                      <% end %>
                    <% "timeseries" -> %>
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div class="sm:col-span-2">
                          <% paths = timeseries_paths_for_form(@editing_widget["paths"]) %>
                          <% paths_length = length(paths) %>
                          <div
                            id={"widget-#{@editing_widget["id"]}-timeseries-paths"}
                            phx-hook="TimeseriesPaths"
                            data-widget-id={@editing_widget["id"]}
                            class="space-y-3"
                          >
                            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
                              Paths
                            </label>
                            <div class="space-y-2">
                              <%= for {path, index} <- Enum.with_index(paths) do %>
                                <div class="flex items-center gap-2">
                                  <div class="flex-1 min-w-0">
                                    <.path_autocomplete_input
                                      id={"widget-ts-path-#{@editing_widget["id"]}-#{index}"}
                                      name="ts_paths[]"
                                      value={path}
                                      placeholder="metrics.sales"
                                      path_options={@widget_path_options}
                                      input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                                    />
                                  </div>
                                  <button
                                    type="button"
                                    data-action="remove"
                                    data-index={index}
                                    class="inline-flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-md bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                                    aria-label="Remove path"
                                    disabled={paths_length == 1}
                                  >
                                    &minus;
                                  </button>
                                </div>
                              <% end %>
                            </div>
                            <button
                              type="button"
                              data-action="add"
                              class="inline-flex items-center gap-1 rounded-md bg-teal-500 px-3 py-2 text-sm font-medium text-white hover:bg-teal-600 dark:bg-teal-600 dark:hover:bg-teal-500"
                            >
                              <span aria-hidden="true">+</span>
                              <span class="sr-only">Add path</span>
                            </button>
                            <p class="text-xs text-gray-500 dark:text-slate-400">
                              Use <code>*</code>
                              to include nested keys (for example <code>breakdown.*</code>). Parent paths automatically expand when matching children exist.
                            </p>
                          </div>
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            Y-axis label
                          </label>
                          <input
                            type="text"
                            name="ts_y_label"
                            value={@editing_widget["y_label"] || ""}
                            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                            placeholder="e.g., Revenue ($), Orders, Errors (%)"
                          />
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            Chart Type
                          </label>
                          <% ctype = @editing_widget["chart_type"] || "line" %>
                          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                            <select
                              name="ts_chart_type"
                              class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                            >
                              <option value="line" selected={ctype == "line"}>Line</option>
                              <option value="area" selected={ctype == "area"}>Area</option>
                              <option value="bar" selected={ctype == "bar"}>Bar</option>
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
                        <div class="flex items-center gap-4 sm:col-span-2">
                          <% stacked = @editing_widget["stacked"] || false %>
                          <% normalized = @editing_widget["normalized"] || false %>
                          <% legend = @editing_widget["legend"] || false %>
                          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                            <input type="checkbox" name="ts_stacked" checked={stacked} /> Stacked
                          </label>
                          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                            <input type="checkbox" name="ts_normalized" checked={normalized} />
                            Normalized
                          </label>
                          <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                            <input type="checkbox" name="ts_legend" checked={legend} /> Show legend
                          </label>
                        </div>
                      </div>
                    <% "text" -> %>
                      <% subtype = normalize_text_subtype(@editing_widget["subtype"]) %>
                      <% color_id = normalize_text_color_id(@editing_widget["color"]) %>
                      <% size = normalize_text_title_size(@editing_widget["title_size"]) %>
                      <% alignment = normalize_text_alignment(@editing_widget["alignment"]) %>
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            Content Type
                          </label>
                          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                            <select
                              name="text_subtype"
                              class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                              phx-change="change_text_subtype"
                              phx-value-widget-id={@editing_widget["id"]}
                            >
                              <option value="header" selected={subtype == "header"}>Header</option>
                              <option value="html" selected={subtype == "html"}>HTML</option>
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
                            Background color
                          </label>
                          <% selected_color = resolve_text_widget_color(color_id) %>
                          <div x-data="{ open: false }" class="relative mt-2 sm:max-w-xs" x-cloak>
                            <input type="hidden" name="text_color" value={color_id} />
                            <button
                              type="button"
                              class="w-full h-10 cursor-default rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 py-2 pl-3 pr-10 text-left text-sm font-medium text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
                              x-on:click="open = !open"
                              x-bind:aria-expanded="open"
                              aria-haspopup="listbox"
                            >
                              <div class="flex items-center justify-between">
                                <span>{selected_color.label}</span>
                                <span class="inline-flex items-center gap-2">
                                  <span
                                    class="inline-block h-5 w-5 rounded-md border border-white/80 shadow-sm"
                                    style={"background-color: #{selected_color.background};"}
                                    aria-hidden="true"
                                  >
                                  </span>
                                </span>
                              </div>
                              <span class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
                                <svg
                                  class="h-5 w-5 text-gray-400"
                                  fill="none"
                                  viewBox="0 0 24 24"
                                  stroke="currentColor"
                                >
                                  <path
                                    stroke-linecap="round"
                                    stroke-linejoin="round"
                                    stroke-width="2"
                                    d="M19 9l-7 7-7-7"
                                  />
                                </svg>
                              </span>
                            </button>

                            <div
                              x-show="open"
                              x-on:click.away="open = false"
                              class="absolute z-50 mt-1 w-full max-h-60 overflow-auto rounded-md bg-white dark:bg-slate-800 py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm"
                              role="listbox"
                            >
                              <%= for color <- text_widget_color_options() do %>
                                <button
                                  type="button"
                                  phx-click="change_text_color"
                                  phx-value-widget-id={@editing_widget["id"]}
                                  phx-value-color={color.id}
                                  x-on:click="open = false"
                                  class={[
                                    "w-full text-left px-3 py-2 hover:bg-gray-100 dark:hover:bg-slate-600 cursor-pointer",
                                    if(color_id == color.id, do: "bg-gray-100 dark:bg-slate-700")
                                  ]}
                                  role="option"
                                  aria-selected={color_id == color.id}
                                >
                                  <div class="flex items-center justify-between">
                                    <span class="text-sm text-gray-900 dark:text-white">
                                      {color.label}
                                    </span>
                                    <span class="inline-flex items-center">
                                      <span
                                        class="inline-block h-5 w-5 rounded-md border border-white/80 shadow-sm"
                                        style={"background-color: #{color.background};"}
                                        aria-hidden="true"
                                      >
                                      </span>
                                    </span>
                                  </div>
                                </button>
                              <% end %>
                            </div>
                          </div>
                        </div>
                      </div>

                      <%= if subtype == "html" do %>
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            HTML Content
                          </label>
                          <textarea
                            name="text_payload"
                            rows="6"
                            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                            placeholder="<h2>Hello world</h2>"
                          ><%= @editing_widget["payload"] || "" %></textarea>
                          <p class="mt-1 text-xs text-amber-600 dark:text-amber-400">
                            Raw HTML is inserted as-is. Make sure it comes from a trusted source.
                          </p>
                        </div>
                      <% else %>
                        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                          <div>
                            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                              Title Size
                            </label>
                            <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                              <select
                                name="text_title_size"
                                class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                              >
                                <option value="large" selected={size == "large"}>Large</option>
                                <option value="medium" selected={size == "medium"}>Medium</option>
                                <option value="small" selected={size == "small"}>Small</option>
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
                              Alignment
                            </label>
                            <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                              <select
                                name="text_alignment"
                                class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                              >
                                <option value="left" selected={alignment == "left"}>Left</option>
                                <option value="center" selected={alignment == "center"}>
                                  Center
                                </option>
                                <option value="right" selected={alignment == "right"}>Right</option>
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
                          <div class="sm:col-span-2">
                            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                              Subtitle
                            </label>
                            <textarea
                              name="text_subtitle"
                              rows="3"
                              class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                              placeholder="Optional supporting text"
                            ><%= @editing_widget["subtitle"] || "" %></textarea>
                          </div>
                        </div>
                      <% end %>
                    <% "category" -> %>
                      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                        <div class="sm:col-span-2">
                          <% cat_paths = category_paths_for_form(@editing_widget || %{}) %>
                          <% cat_paths_length = length(cat_paths) %>
                          <div
                            id={"widget-#{@editing_widget["id"]}-category-paths"}
                            phx-hook="CategoryPaths"
                            data-widget-id={@editing_widget["id"]}
                            class="space-y-3"
                          >
                            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
                              Paths
                            </label>
                            <div class="space-y-2">
                              <%= for {path, index} <- Enum.with_index(cat_paths) do %>
                                <div class="flex items-center gap-2">
                                  <div class="flex-1 min-w-0">
                                    <.path_autocomplete_input
                                      id={"widget-cat-path-#{@editing_widget["id"]}-#{index}"}
                                      name="cat_paths[]"
                                      value={path}
                                      placeholder="metrics.category"
                                      path_options={@widget_path_options}
                                      input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                                    />
                                  </div>
                                  <button
                                    type="button"
                                    data-action="remove"
                                    data-index={index}
                                    class="inline-flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-md bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                                    aria-label="Remove path"
                                    disabled={cat_paths_length == 1}
                                  >
                                    &minus;
                                  </button>
                                </div>
                              <% end %>
                            </div>
                            <button
                              type="button"
                              data-action="add"
                              class="inline-flex items-center gap-1 rounded-md bg-teal-500 px-3 py-2 text-sm font-medium text-white hover:bg-teal-600 dark:bg-teal-600 dark:hover:bg-teal-500"
                            >
                              <span aria-hidden="true">+</span>
                              <span class="sr-only">Add path</span>
                            </button>
                            <p class="text-xs text-gray-500 dark:text-slate-400">
                              Use <code>*</code>
                              to include nested keys (for example <code>breakdown.*</code>). Parent paths automatically expand when matching children exist.
                            </p>
                          </div>
                        </div>
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                            Chart Type
                          </label>
                          <% ctype = @editing_widget["chart_type"] || "bar" %>
                          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                            <select
                              name="cat_chart_type"
                              class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
                            >
                              <option value="bar" selected={ctype == "bar"}>Bar</option>
                              <option value="pie" selected={ctype == "pie"}>Pie</option>
                              <option value="donut" selected={ctype == "donut"}>Donut</option>
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
                      </div>
                  <% end %>

                  <div class="flex items-center justify-end gap-3 pt-2">
                    <button
                      type="button"
                      phx-click="close_widget_editor"
                      class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                    >
                      Cancel
                    </button>
                    <button
                      type="submit"
                      class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                    >
                      Save
                    </button>
                  </div>
                </.form>
                
    <!-- Danger Zone -->
                <div class="border-t border-gray-200 dark:border-slate-600 pt-4">
                  <h3 class="text-sm font-medium text-red-600 dark:text-red-400">Danger Zone</h3>
                  <p class="text-xs text-gray-500 dark:text-slate-400">
                    Delete this widget permanently from the dashboard.
                  </p>
                  <div class="mt-3">
                    <button
                      type="button"
                      phx-click="delete_widget"
                      phx-value-id={@editing_widget["id"]}
                      data-confirm="Are you sure you want to delete this widget? This action cannot be undone."
                      class="inline-flex items-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                    >
                      Delete Widget
                    </button>
                  </div>
                </div>
              </div>
            </:body>
          </.app_modal>
        <% end %>
        
    <!-- Expanded Widget Modal -->
        <%= if @expanded_widget do %>
          <.app_modal
            id="widget-expand-modal"
            show={true}
            size="full"
            on_cancel={JS.push("close_expanded_widget")}
          >
            <:title>
              <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
                <div class="flex items-center gap-3">
                  <span>{@expanded_widget.title}</span>
                  <span class="inline-flex items-center rounded-full bg-teal-100/70 dark:bg-teal-900/40 px-3 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200">
                    {String.capitalize(@expanded_widget.type || "widget")}
                  </span>
                </div>
              </div>
            </:title>
            <:body>
              <div
                id={"expanded-widget-#{@expanded_widget.widget_id}"}
                class="h-[80vh] flex flex-col gap-6 overflow-y-auto"
                phx-hook="ExpandedWidgetView"
                data-type={@expanded_widget.type}
                data-title={@expanded_widget.title}
                data-colors={ChartColors.json_palette()}
                data-chart={
                  if @expanded_widget[:chart_data],
                    do: Jason.encode!(@expanded_widget.chart_data)
                }
                data-visual={
                  if @expanded_widget[:visual_data],
                    do: Jason.encode!(@expanded_widget.visual_data)
                }
                data-text={
                  if @expanded_widget[:text_data],
                    do: Jason.encode!(@expanded_widget.text_data)
                }
              >
                <div class="flex-1 min-h-[500px]">
                  <div class="h-full w-full rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                    <div data-role="chart" class="h-full w-full"></div>
                  </div>
                </div>
                <div class="flex-1 min-h-[300px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/60 overflow-auto">
                  <div data-role="table-root" class="h-full w-full overflow-auto"></div>
                </div>
              </div>
            </:body>
          </.app_modal>
        <% end %>
        
    <!-- Dashboard Content -->
        <div class="flex-1 relative">
          <%= if !has_grid_items do %>
            <!-- Empty state in white panel -->
            <div class="bg-white dark:bg-slate-800 rounded-lg shadow relative">
              <div class="p-6">
                <!-- Empty state -->
                <div class="text-center py-12">
                  <svg
                    class="mx-auto h-12 w-12 text-gray-400"
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
                  <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">
                    Dashboard is empty
                  </h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
                    This dashboard doesn't have any visualization data yet. Hit the Add Widget button and give it something to show off.
                  </p>
                  <%= if !@is_public_access do %>
                    <% add_btn_id = "dashboard-" <> @dashboard.id <> "-add-widget" %>
                    <div class="mt-6">
                      <button
                        type="button"
                        phx-click={JS.dispatch("click", to: "##{add_btn_id}")}
                        class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                      >
                        <svg
                          class="-ml-0.5 mr-1.5 h-5 w-5"
                          xmlns="http://www.w3.org/2000/svg"
                          fill="none"
                          viewBox="0 0 24 24"
                          stroke-width="1.5"
                          stroke="currentColor"
                        >
                          <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v12m6-6H6" />
                        </svg>
                        Add Widget
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </main>
      
    <!-- Sticky Summary Footer (only for authenticated users) -->
      <%= if !@is_public_access do %>
        <%= if summary = get_summary_stats(assigns) do %>
          <.dashboard_footer
            class="mt-auto"
            summary={summary}
            load_duration_microseconds={@load_duration_microseconds}
            show_export_dropdown={@show_export_dropdown}
            dashboard={@dashboard}
            export_params={
              build_url_params(%{
                granularity: @granularity,
                smart_timeframe_input: @smart_timeframe_input,
                use_fixed_display: @use_fixed_display,
                from: @from,
                to: @to,
                segment_values: @segment_values
              })
              |> then(fn params ->
                cond do
                  is_binary(@resolved_key) and @resolved_key != "" ->
                    Map.put(params, "key", @resolved_key)

                  true ->
                    params
                end
              end)
            }
          />
        <% end %>
      <% end %>
    </div>
    """
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
          # Propose next window
          proposed_to = DateTime.add(to, duration_seconds, :second)
          # Clamp to current time in configured timezone
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

  defp group_sources_for_select(sources) do
    sources
    |> Enum.group_by(&Source.type/1)
    |> Enum.map(fn {type, list} -> {Source.type_label(type), list} end)
    |> Enum.sort_by(fn {label, _} -> label end)
  end

  defp source_option_value(source) do
    type = source |> Source.type() |> Atom.to_string()
    id = source |> Source.id() |> to_string()
    "#{type}:#{id}"
  end

  defp source_selected?(nil, _source), do: false

  defp source_selected?(%{type: type, id: id}, source) do
    type == Source.type(source) && id == to_string(Source.id(source))
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
end
