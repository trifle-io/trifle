defmodule TrifleApp.DashboardLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Stats.SeriesFetcher
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing
  require Logger

  def mount(params, _session, socket) do
    case params do
      %{"id" => dashboard_id} ->
        # Authenticated access; fetch dashboard and associated database
        dashboard = Organizations.get_dashboard!(dashboard_id)
        database = dashboard.database

        socket = initialize_dashboard_state(socket, database, dashboard, false, nil)

        groups = Organizations.get_dashboard_group_chain(dashboard.group_id)
        breadcrumbs = [{"Dashboards", "/app/dashboards"}] ++ Enum.map(groups, &{&1.name, "/app/dashboards"}) ++ [dashboard.name]
        {:ok,
         socket
         |> assign(:page_title, ["Dashboards", dashboard.name])
         |> assign(:breadcrumb_links, breadcrumbs)}

      %{"dashboard_id" => dashboard_id} ->
        # Public access - token will be provided in handle_params
        {:ok,
         socket
         |> assign(:is_public_access, true)
         |> assign(:public_token, nil)
         |> assign(:dashboard_id, dashboard_id)}
    end
  end

  def handle_params(params, _url, socket) do
    if socket.assigns.is_public_access do
      # Handle public access with token verification
      token = params["token"]
      dashboard_id = socket.assigns.dashboard_id

      case Organizations.get_dashboard_by_token(dashboard_id, token) do
        {:ok, dashboard} ->
          # Initialize dashboard data state for public access
          socket = initialize_dashboard_state(socket, dashboard.database, dashboard, true, token)

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
    socket = socket
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
    databases = Organizations.list_databases()

    socket
    |> assign(:dashboard_changeset, nil)
    |> assign(:dashboard_form, nil)
    |> assign(:temp_name, socket.assigns.dashboard.name)
    |> assign(:databases, databases)
  end


  def handle_event("update_temp_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, :temp_name, name)}
  end

  def handle_event("save_name", %{"name" => name}, socket) do
    dashboard = socket.assigns.dashboard

    case Organizations.update_dashboard(dashboard, %{name: name}) do
      {:ok, updated_dashboard} ->
        # Update breadcrumbs and page title with new dashboard name
        groups = Organizations.get_dashboard_group_chain(updated_dashboard.group_id)
        updated_breadcrumbs = [{"Dashboards", "/app/dashboards"}] ++ Enum.map(groups, &{&1.name, "/app/dashboards"}) ++ [updated_dashboard.name]
        updated_page_title = ["Dashboards", updated_dashboard.name]

        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> assign(:temp_name, updated_dashboard.name)
         |> assign(:breadcrumb_links, updated_breadcrumbs)
         |> assign(:page_title, updated_page_title)
         |> put_flash(:info, "Dashboard name updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update dashboard name")}
    end
  end

  def handle_event("toggle_visibility", _params, socket) do
    dashboard = socket.assigns.dashboard

    case Organizations.update_dashboard(dashboard, %{visibility: !dashboard.visibility}) do
      {:ok, updated_dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> put_flash(:info, "Dashboard visibility updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update dashboard visibility")}
    end
  end

  def handle_event("generate_public_token", _params, socket) do
    dashboard = socket.assigns.dashboard

    case Organizations.generate_dashboard_public_token(dashboard) do
      {:ok, updated_dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> put_flash(:info, "Public link generated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to generate public link")}
    end
  end


  def handle_event("remove_public_token", _params, socket) do
    dashboard = socket.assigns.dashboard

    case Organizations.remove_dashboard_public_token(dashboard) do
      {:ok, updated_dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> put_flash(:info, "Public link removed successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to remove public link")}
    end
  end

  def handle_event("delete_dashboard", _params, socket) do
    dashboard = socket.assigns.dashboard

    case Organizations.delete_dashboard(dashboard) do
      {:ok, _} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/app/dashboards")
         |> put_flash(:info, "Dashboard deleted successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to delete dashboard")}
    end
  end

  def handle_event("duplicate_dashboard", _params, socket) do
    original = socket.assigns.dashboard
    database = socket.assigns.database
    current_user = socket.assigns.current_user

    attrs = %{
      "database_id" => database.id,
      "user_id" => current_user.id,
      "name" => (original.name || "Dashboard") <> " (copy)",
      "key" => original.key || "dashboard",
      "payload" => original.payload || %{},
      "default_timeframe" => original.default_timeframe || database.default_timeframe || "24h",
      "default_granularity" => original.default_granularity || database.default_granularity || "1h",
      "visibility" => original.visibility,
      "group_id" => original.group_id,
      "position" => Organizations.get_next_dashboard_position_for_group(original.group_id)
    }

    case Organizations.create_dashboard(attrs) do
      {:ok, new_dash} ->
        {:noreply,
         socket
         |> put_flash(:info, "Dashboard duplicated")
         |> push_navigate(to: ~p"/app/dashboards/#{new_dash.id}")}

      {:error, _cs} ->
        {:noreply, put_flash(socket, :error, "Could not duplicate dashboard")}
    end
  end

  def handle_event("save_dashboard", %{"dashboard" => dashboard_params}, socket) do
    case Organizations.update_dashboard(socket.assigns.dashboard, dashboard_params) do
      {:ok, dashboard} ->
        {:noreply,
         socket
         |> assign(:dashboard, dashboard)
         |> assign(:dashboard_changeset, nil)
         |> assign(:dashboard_form, nil)
         |> push_patch(to: ~p"/app/dashboards/#{dashboard.id}")
         |> put_flash(:info, "Dashboard updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:dashboard_changeset, changeset)
         |> assign(:dashboard_form, to_form(changeset))}
    end
  end

  # Persist Grid layout changes from client (GridStack)
  def handle_event("dashboard_grid_changed", %{"items" => items}, socket) do
    cond do
      socket.assigns.is_public_access -> {:noreply, socket}
      is_nil(socket.assigns[:current_user]) -> {:noreply, socket}
      socket.assigns.dashboard.user_id != socket.assigns.current_user.id -> {:noreply, socket}
      true ->
        dashboard = socket.assigns.dashboard
        existing = (dashboard.payload || %{})["grid"] || []
        by_id = Map.new(existing, fn i -> {to_string(i["id"]), i} end)
        merged = Enum.map(items, fn item ->
          id = to_string(item["id"]) 
          prev = Map.get(by_id, id, %{})
          Map.merge(prev, item)
        end)
        payload = Map.put(dashboard.payload || %{}, "grid", merged)
        case Organizations.update_dashboard(dashboard, %{payload: payload}) do
          {:ok, updated_dashboard} ->
            # If stats are loaded, recompute KPI values (in case new widgets were added)
            socket = assign(socket, :dashboard, updated_dashboard)
            socket =
              if socket.assigns[:stats] do
                items = updated_dashboard.payload["grid"] || []
                kpi_items = compute_kpi_values(socket.assigns.stats, items)
                kpi_lines = compute_kpi_sparklines(socket.assigns.stats, items)
                ts_items = compute_timeseries_widgets(socket.assigns.stats, items)
                cat_items = compute_category_widgets(socket.assigns.stats, items)
                socket
                |> push_event("dashboard_grid_kpi_values", %{items: kpi_items})
                |> push_event("dashboard_grid_kpi_sparkline", %{items: kpi_lines})
                |> push_event("dashboard_grid_timeseries", %{items: ts_items})
                |> push_event("dashboard_grid_category", %{items: cat_items})
              else
                socket
              end
            {:noreply, socket}
          {:error, _} -> {:noreply, socket}
        end
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:dashboard_changeset, nil)
     |> assign(:dashboard_form, nil)
     |> push_patch(to: ~p"/app/dashboards/#{socket.assigns.dashboard.id}")}
  end

  # Widget editing modal controls
  def handle_event("open_widget_editor", %{"id" => id}, socket) do
    cond do
      socket.assigns.is_public_access -> {:noreply, socket}
      is_nil(socket.assigns[:current_user]) -> {:noreply, socket}
      socket.assigns.dashboard.user_id != socket.assigns.current_user.id -> {:noreply, socket}
      true ->
        items = socket.assigns.dashboard.payload["grid"] || []
        widget = Enum.find(items, fn i -> to_string(i["id"]) == to_string(id) end)
        widget = (widget || %{"id" => id, "title" => ""}) |> Map.put_new("type", "kpi")
        {:noreply, assign(socket, :editing_widget, widget)}
    end
  end

  def handle_event("close_widget_editor", _params, socket) do
    {:noreply, assign(socket, :editing_widget, nil)}
  end

  def handle_event("save_widget", params, socket) do
    %{"widget_id" => id} = params
    title = String.trim(to_string(Map.get(params, "widget_title", "")))
    type = String.downcase(Map.get(params, "widget_type", "kpi"))

    cond do
      socket.assigns.is_public_access -> {:noreply, socket}
      is_nil(socket.assigns[:current_user]) -> {:noreply, socket}
      socket.assigns.dashboard.user_id != socket.assigns.current_user.id -> {:noreply, socket}
      true ->
        items = socket.assigns.dashboard.payload["grid"] || []
        updated = Enum.map(items, fn i ->
          if to_string(i["id"]) == to_string(id) do
            base = i |> Map.put("title", title) |> Map.put("type", type)
            case type do
              "kpi" ->
                base
                |> Map.put("path", Map.get(params, "kpi_path", ""))
                |> Map.put("function", Map.get(params, "kpi_function", "mean"))
                |> Map.put("split", Map.has_key?(params, "kpi_split"))
                |> Map.put("diff", Map.has_key?(params, "kpi_diff"))
                |> Map.put("timeseries", Map.has_key?(params, "kpi_timeseries"))
                |> Map.put("size", Map.get(params, "kpi_size", "m"))
              "timeseries" ->
                paths =
                  params
                  |> Map.get("ts_paths", "")
                  |> String.split(["\n", "\r"], trim: true)
                  |> Enum.map(&String.trim/1)
                  |> Enum.reject(&(&1 == ""))
                base
                |> Map.put("paths", paths)
                |> Map.put("chart_type", Map.get(params, "ts_chart_type", "line"))
                |> Map.put("stacked", Map.has_key?(params, "ts_stacked"))
                |> Map.put("normalized", Map.has_key?(params, "ts_normalized"))
                |> Map.put("legend", Map.has_key?(params, "ts_legend"))
                |> Map.put("y_label", Map.get(params, "ts_y_label", ""))
              "category" ->
                base
                |> Map.put("path", Map.get(params, "cat_path", ""))
                |> Map.put("chart_type", Map.get(params, "cat_chart_type", "bar"))
              _ -> base
            end
          else
            i
          end
        end)

        payload = Map.put(socket.assigns.dashboard.payload || %{}, "grid", updated)
        case Organizations.update_dashboard(socket.assigns.dashboard, %{payload: payload}) do
          {:ok, dashboard} ->
            # After saving, recompute KPI values if stats already loaded
            socket = socket |> assign(:dashboard, dashboard) |> assign(:editing_widget, nil)
            socket =
              if socket.assigns[:stats] do
                items = dashboard.payload["grid"] || []
                kpi_items = compute_kpi_values(socket.assigns.stats, items)
                kpi_lines = compute_kpi_sparklines(socket.assigns.stats, items)
                ts_items = compute_timeseries_widgets(socket.assigns.stats, items)
                cat_items = compute_category_widgets(socket.assigns.stats, items)
                socket
                |> push_event("dashboard_grid_kpi_values", %{items: kpi_items})
                |> push_event("dashboard_grid_kpi_sparkline", %{items: kpi_lines})
                |> push_event("dashboard_grid_timeseries", %{items: ts_items})
                |> push_event("dashboard_grid_category", %{items: cat_items})
              else
                socket
              end
            {:noreply,
             socket
             |> push_event("dashboard_grid_widget_updated", %{id: id, title: title})}
          {:error, _} -> {:noreply, socket}
        end
    end
  end

  def handle_event("change_widget_type", %{"widget_id" => id, "widget_type" => type}, socket) do
    w = socket.assigns.editing_widget || %{"id" => id}
    {:noreply, assign(socket, :editing_widget, Map.put(w, "type", String.downcase(type)))}
  end

  def handle_event("delete_widget", %{"id" => id}, socket) do
    cond do
      socket.assigns.is_public_access -> {:noreply, socket}
      is_nil(socket.assigns[:current_user]) -> {:noreply, socket}
      socket.assigns.dashboard.user_id != socket.assigns.current_user.id -> {:noreply, socket}
      true ->
        items = socket.assigns.dashboard.payload["grid"] || []
        updated = Enum.reject(items, fn i -> to_string(i["id"]) == to_string(id) end)
        payload = Map.put(socket.assigns.dashboard.payload || %{}, "grid", updated)
        case Organizations.update_dashboard(socket.assigns.dashboard, %{payload: payload}) do
          {:ok, dashboard} ->
            {:noreply,
             socket
             |> assign(:dashboard, dashboard)
             |> assign(:editing_widget, nil)
             |> push_event("dashboard_grid_widget_deleted", %{id: id})}
          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  # Compute KPI values for KPI widgets from current series
  defp compute_kpi_values(series_struct, grid_items) do
    grid_items
    |> Enum.filter(fn item -> String.downcase(to_string(item["type"] || "kpi")) == "kpi" end)
    |> Enum.map(fn item ->
      id = to_string(item["id"]) 
      path = to_string(item["path"] || "")
      func = String.downcase(to_string(item["function"] || "mean"))
      size = to_string(item["size"] || "m")
      split = !!item["split"]
      diff = !!item["diff"]
      slices = if split, do: 2, else: 1
      list = aggregate_for_function(series_struct, path, func, slices) |> List.wrap()
      if split do
        len = length(list)
        prev = if len >= 2, do: Enum.at(list, len - 2), else: nil
        curr = if len >= 1, do: Enum.at(list, len - 1), else: nil
        %{id: id, split: true, diff: diff, size: size, previous: to_number(prev), current: to_number(curr)}
      else
        value = list |> List.first()
        %{id: id, split: false, size: size, value: to_number(value)}
      end
    end)
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
  defp to_number(_), do: nil

  # Build sparkline points for KPI widgets that have timeseries enabled
  defp compute_kpi_sparklines(series_struct, grid_items) do
    grid_items
    |> Enum.filter(fn item ->
      String.downcase(to_string(item["type"] || "kpi")) == "kpi" and (item["timeseries"] || false)
    end)
    |> Enum.map(fn item ->
      id = to_string(item["id"]) 
      path = to_string(item["path"] || "")
      points = Trifle.Stats.Series.format_timeline(series_struct, path, 1, fn at, value ->
        # Convert to ms timestamp for ECharts
        # Keep local wall time representation by reinterpreting naive as UTC (aligns with Explore)
        naive = DateTime.to_naive(at)
        utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
        ts = DateTime.to_unix(utc_dt, :millisecond)
        val = cond do
          match?(%Decimal{}, value) -> Decimal.to_float(value)
          is_number(value) -> value * 1.0
          true -> 0.0
        end
        [ts, val]
      end)
      %{id: id, data: points}
    end)
  end

  # Build timeseries chart data for timeseries widgets
  defp compute_timeseries_widgets(series_struct, grid_items) do
    items = grid_items
    |> Enum.filter(fn item -> String.downcase(to_string(item["type"] || "")) == "timeseries" end)
    |> Enum.map(fn item ->
      id = to_string(item["id"]) 
      paths = (item["paths"] || []) |> Enum.map(&to_string/1)
      chart_type = String.downcase(to_string(item["chart_type"] || "line"))
      stacked = !!item["stacked"]
      normalized = !!item["normalized"]
      legend = !!item["legend"]
      y_label = to_string(item["y_label"] || "")

      # Use formatter to align timeline and values per path
      per_path = Enum.map(paths, fn path ->
        data = Trifle.Stats.Series.format_timeline(series_struct, path, 1, fn at, value ->
          naive = DateTime.to_naive(at)
          utc_dt = DateTime.from_naive!(naive, "Etc/UTC")
          ts = DateTime.to_unix(utc_dt, :millisecond)
          val = case value do
            %Decimal{} = d -> Decimal.to_float(d)
            v when is_number(v) -> v * 1.0
            _ -> 0.0
          end
          [ts, val]
        end) || []
        %{name: path, data: data}
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

                total = Enum.reduce(per_path, 0.0, fn other, acc ->
                  ov = case Enum.at(other.data, idx) do
                    [_, ovv] -> ovv
                    {_, ovv} -> ovv
                    _ -> 0.0
                  end
                  acc + (ov || 0.0)
                end)

                pct = if total > 0.0 and is_number(v), do: (v / total) * 100.0, else: 0.0
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
      summary = Enum.map(items, fn i ->
        %{id: i.id, series: Enum.map(i.series, fn s -> %{name: s.name, points: length(s.data)} end)}
      end)
      "Timeseries widgets: " <> inspect(summary)
    end)
    items
  end

  # Build category chart data for category widgets using the formatter
  defp compute_category_widgets(series_struct, grid_items) do
    items = grid_items
    |> Enum.filter(fn item -> String.downcase(to_string(item["type"] || "")) == "category" end)
    |> Enum.map(fn item ->
      id = to_string(item["id"]) 
      path = to_string(item["path"] || "")
      chart_type = String.downcase(to_string(item["chart_type"] || "bar"))

      # Use format_category to aggregate across timeframe. With slices=2 we avoid the single-slice
      # timeline return and get maps we can merge into a single total category map.
      formatted = Trifle.Stats.Series.format_category(series_struct, path, 2)

      merged_map =
        cond do
          is_list(formatted) ->
            formatted
            |> Enum.filter(&is_map/1)
            |> Enum.reduce(%{}, fn m, acc ->
              Map.merge(acc, m, fn _k, a, b -> normalize_number(a) + normalize_number(b) end)
            end)
          is_map(formatted) -> formatted
          true -> %{}
        end

      data =
        merged_map
        |> Enum.map(fn {k, v} -> %{name: to_string(k), value: normalize_number(v)} end)
        |> Enum.sort_by(& &1.name)

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

  defp normalize_number(%Decimal{} = d), do: Decimal.to_float(d)
  defp normalize_number(v) when is_number(v), do: v * 1.0
  defp normalize_number(_), do: 0.0

  # Filter bar message handling
  def handle_info({:filter_bar, {:filter_changed, changes}}, socket) do
    # Update socket with filter changes from FilterBar component
    socket = Enum.reduce(changes, socket, fn {key, value}, acc ->
      case key do
        :from -> assign(acc, :from, value)
        :to -> assign(acc, :to, value)
        :granularity -> assign(acc, :granularity, value)
        :smart_timeframe_input -> assign(acc, :smart_timeframe_input, value)
        :use_fixed_display -> assign(acc, :use_fixed_display, value)
        :reload -> acc  # Just trigger reload
        _ -> acc
      end
    end)

    # Update URL with new parameters
    params = build_url_params(socket)
    path = if socket.assigns.is_public_access do
      ~p"/d/#{socket.assigns.dashboard.id}?#{params}"
    else
      ~p"/app/dashboards/#{socket.assigns.dashboard.id}?#{params}"
    end

    socket = push_patch(socket, to: path)

    # Reload dashboard data
    socket = if dashboard_has_key?(socket) do
      load_dashboard_data(socket)
    else
      socket
    end

    {:noreply, socket}
  end

  # Progress message handling
  def handle_info({:loading_progress, progress_map}, socket) do
    {:noreply, assign(socket, :loading_progress, progress_map)}
  end

  def handle_info({:transponding, state}, socket) do
    {:noreply, assign(socket, :transponding, state)}
  end

  # Dashboard Data Management

  defp initialize_dashboard_state(socket, database, dashboard, is_public_access, public_token) do
    # Parse timeframe from URL or use default
    {from, to, granularity, smart_timeframe_input, use_fixed_display} = get_default_timeframe_params(database)

    # Cache config to avoid recalculation on every render
    database_config = Database.stats_config(database)
    available_granularities = get_available_granularities(database)

    # Load transponders to identify response paths and their names
    transponders = Organizations.list_transponders_for_database(database)
    transponder_info = transponders
    |> Enum.map(fn transponder ->
      response_path = Map.get(transponder.config, "response_path", "")
      transponder_name = transponder.name || transponder.key
      if response_path != "", do: {response_path, transponder_name}, else: nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})

    transponder_response_paths = Map.keys(transponder_info)

    socket
    |> assign(:database, database)
    |> assign(:dashboard, dashboard)
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
  end

  defp apply_url_params(socket, params) do
    # Parse URL parameters for filters
    config = socket.assigns.database_config

    defaults = %{
      default_timeframe: socket.assigns.dashboard.default_timeframe || socket.assigns.database.default_timeframe,
      default_granularity: socket.assigns.dashboard.default_granularity || socket.assigns.database.default_granularity
    }

    {from, to, granularity, smart_timeframe_input, use_fixed_display} =
      UrlParsing.parse_url_params(params, config, socket.assigns.available_granularities, defaults)

    socket
    |> assign(:from, from)
    |> assign(:to, to)
    |> assign(:granularity, granularity)
    |> assign(:smart_timeframe_input, smart_timeframe_input)
    |> assign(:use_fixed_display, use_fixed_display)
  end

  defp get_default_timeframe_params(database) do
    config = Database.stats_config(database)
    granularities = get_available_granularities(database)

    # Use database defaults if present
    default_tf = database.default_timeframe || "24h"
    default_gran = database.default_granularity || "1h"

    case TimeframeParsing.parse_smart_timeframe(default_tf, config) do
      {:ok, from, to, smart_input, use_fixed} ->
        gran = if Enum.member?(granularities, default_gran), do: default_gran, else: Enum.at(granularities, 3, "1h")
        {from, to, gran, smart_input, use_fixed}
      {:error, _} ->
        # Fallback
        now = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
        from = DateTime.add(now, -24 * 60 * 60, :second)
        {from, now, "1h", "24h", false}
    end
  end

  defp get_available_granularities(database) do
    config = Database.stats_config(database)
    config.track_granularities
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
      socket = assign(socket,
        load_start_time: System.monotonic_time(:microsecond),
        loading: true,
        loading_chunks: true,
        loading_progress: nil,
        transponding: false
      )

      # Extract values to avoid async socket warnings
      database = socket.assigns.database
      key = socket.assigns.dashboard.key
      granularity = socket.assigns.granularity
      from = socket.assigns.from
      to = socket.assigns.to
      liveview_pid = self() # Capture LiveView PID before async task

      start_async(socket, :dashboard_data_task, fn ->
        # Get transponders that match the dashboard key
        matching_transponders = Organizations.list_transponders_for_database(database)
        |> Enum.filter(&(&1.enabled))
        |> Enum.filter(fn transponder -> key_matches_pattern?(key, transponder.key) end)
        |> Enum.sort_by(& &1.order)

        # Create progress callback to send updates back to LiveView
        progress_callback = fn progress_info ->
          case progress_info do
            {:chunk_progress, current, total} ->
              send(liveview_pid, {:loading_progress, %{current: current, total: total}})
            {:transponder_progress, :starting} ->
              send(liveview_pid, {:transponding, true})
          end
        end

        case SeriesFetcher.fetch_series(database, key, from, to, granularity, matching_transponders, progress_callback: progress_callback) do
          {:ok, result} -> result
          {:error, error} -> {:error, error}
        end
      end)
    else
      socket
    end
  end

  defp build_url_params(socket) do
    base = %{
      "granularity" => socket.assigns.granularity,
      "timeframe" => socket.assigns.smart_timeframe_input || "24h"
    }
    if socket.assigns.use_fixed_display do
      Map.merge(base, %{
        "from" => TimeframeParsing.format_for_datetime_input(socket.assigns.from),
        "to" => TimeframeParsing.format_for_datetime_input(socket.assigns.to)
      })
    else
      base
    end
  end

  def handle_async(:dashboard_data_task, {:ok, result}, socket) do
    # Calculate load duration
    load_duration = System.monotonic_time(:microsecond) - socket.assigns.load_start_time

    # SeriesFetcher now returns %{series: stats, transponder_results: %{successful: [...], failed: [...], errors: [...]}}
    # Compute KPI values for existing widgets, if any
    grid_items = socket.assigns.dashboard.payload["grid"] || []
    kpi_items = compute_kpi_values(result.series, grid_items)
    kpi_lines = compute_kpi_sparklines(result.series, grid_items)
    ts_items = compute_timeseries_widgets(result.series, grid_items)
    cat_items = compute_category_widgets(result.series, grid_items)

    {:noreply,
     socket
     |> assign(loading: false)
     |> assign(loading_chunks: false)
     |> assign(loading_progress: nil)
     |> assign(transponding: false)
     |> assign(stats: result.series)
     |> assign(transponder_results: result.transponder_results)
     |> assign(load_duration_microseconds: load_duration)
     |> push_event("dashboard_grid_kpi_values", %{items: kpi_items})
     |> push_event("dashboard_grid_kpi_sparkline", %{items: kpi_lines})
     |> push_event("dashboard_grid_timeseries", %{items: ts_items})
     |> push_event("dashboard_grid_category", %{items: cat_items})}
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
    hash = email
      |> String.trim()
      |> String.downcase()
      |> :erlang.md5()
      |> Base.encode16(case: :lower)

    "https://www.gravatar.com/avatar/#{hash}?s=150&d=identicon"
  end

  # Summary stats for footer (with transponder statistics)
  def get_summary_stats(assigns) do
    case assigns do
      %{dashboard: %{key: key}, stats: stats, transponder_info: transponder_info, transponder_results: transponder_results} when not is_nil(key) and key != "" and not is_nil(stats) ->
        # Count columns (timeline points)
        column_count = if stats.series[:at], do: length(stats.series[:at]), else: 0

        # Count paths (rows)
        path_count = if stats.series[:paths], do: length(stats.series[:paths]), else: 0

        # Use actual transponder results from SeriesFetcher
        successful_transponders = length(transponder_results.successful)
        failed_transponders = length(transponder_results.failed)
        transponder_errors = transponder_results.errors

        result = %{
          key: key,
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

      %{dashboard: %{key: key}} when not is_nil(key) and key != "" ->
        # Dashboard has key but no stats loaded yet - show basic info
        result = %{
          key: key,
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
        IO.inspect(%{
          has_dashboard: Map.has_key?(assigns, :dashboard),
          dashboard_key: assigns[:dashboard][:key],
          has_stats: Map.has_key?(assigns, :stats),
          stats_nil: is_nil(assigns[:stats]),
          has_transponder_results: Map.has_key?(assigns, :transponder_results)
        }, label: "Dashboard summary stats conditions")
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
      nil -> ""
      series ->
        table = Trifle.Stats.Tabler.tabulize(series)
        at = Enum.reverse(table[:at] || [])
        paths = table[:paths] || []
        values_map = table[:values] || %{}
        header = ["Path" | Enum.map(at, &DateTime.to_iso8601/1)]
        rows = Enum.map(paths, fn path -> [path | Enum.map(at, fn t -> Map.get(values_map, {path, t}) || 0 end)] end)
        [header | rows]
        |> Enum.map(fn cols -> cols |> Enum.map(&csv_escape/1) |> Enum.join(",") end)
        |> Enum.join("\n")
    end
  end

  def handle_event("toggle_export_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_export_dropdown, !(socket.assigns[:show_export_dropdown] || false))}
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
      {:noreply, push_event(socket, "file_download", %{content: csv, filename: fname, type: "text/csv"})}
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
      {:noreply, push_event(socket, "file_download", %{content: json, filename: fname, type: "application/json"})}
    end
  end

  defp export_filename(prefix, assigns, ext) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    base = [prefix, assigns[:dashboard] && assigns.dashboard.name]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.replace(to_string(&1), ~r/[^a-zA-Z0-9_-]+/, "-"))
      |> Enum.join("-")
    (if base == "", do: prefix, else: base) <> "-" <> ts <> ext
  end

  def handle_event("download_dashboard_pdf", _params, socket) do
    # Prefer direct download via controller route to avoid large payloads over LiveView socket
    fname = export_filename("dashboard", socket.assigns, ".pdf")
    url = ~p"/app/export/dashboards/#{socket.assigns.dashboard.id}/pdf?filename=#{fname}"
    {:noreply, push_event(socket, "file_download_url", %{url: url, filename: fname})}
  end

  def handle_event("download_dashboard_png", _params, socket) do
    fname = export_filename("dashboard", socket.assigns, ".png")
    url = ~p"/app/export/dashboards/#{socket.assigns.dashboard.id}/png?filename=#{fname}"
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

  # Toggle Play/Pause from parent LiveView (in case event bubbles up)
  def handle_event("toggle_play_pause", _params, socket) do
    socket =
      if socket.assigns.use_fixed_display do
        # Switch to Play: recompute from/to from current smart timeframe, and mark as live (not fixed)
        tf = socket.assigns.smart_timeframe_input || "24h"
        config = socket.assigns.database_config
        case TimeframeParsing.parse_smart_timeframe(tf, config) do
          {:ok, from, to, smart, _use_fixed} ->
            assign(socket, from: from, to: to, smart_timeframe_input: smart, use_fixed_display: false)
          {:error, _} ->
            assign(socket, use_fixed_display: false)
        end
      else
        # Switch to Pause: keep current from/to and mark fixed
        assign(socket, use_fixed_display: true)
      end

    reload_current_timeframe(socket)
  end

  def handle_event("save_settings", params, socket) do
    dashboard = socket.assigns.dashboard
    name = Map.get(params, "name")
    key = Map.get(params, "key")
    tf = Map.get(params, "timeframe")
    gran = Map.get(params, "granularity")
    new_db_id = Map.get(params, "database_id")

    attrs = %{
      name: String.trim(to_string(name || "")),
      key: String.trim(to_string(key || "")),
      default_timeframe: String.trim(to_string(tf || "")),
      default_granularity: String.trim(to_string(gran || ""))
    }
    attrs = if new_db_id && new_db_id != "", do: Map.put(attrs, :database_id, new_db_id), else: attrs

    case Trifle.Organizations.update_dashboard(dashboard, attrs) do
      {:ok, updated_dashboard} ->
        # If database changed, update assigns and related config
        socket =
          if new_db_id && new_db_id != "" && to_string(socket.assigns.database.id) != to_string(new_db_id) do
            new_db = Organizations.get_database!(new_db_id)
            new_config = Database.stats_config(new_db)
            new_grans = new_db.granularities || []
            socket
            |> assign(:database, new_db)
            |> assign(:database_config, new_config)
            |> assign(:available_granularities, new_grans)
          else
            socket
          end

        # Update breadcrumbs and title to reflect new name
        groups = Organizations.get_dashboard_group_chain(updated_dashboard.group_id)
        updated_breadcrumbs = [{"Dashboards", "/app/dashboards"}] ++ Enum.map(groups, &{&1.name, "/app/dashboards"}) ++ [updated_dashboard.name]
        updated_page_title = ["Dashboards", updated_dashboard.name]

        {:noreply,
         socket
         |> assign(:dashboard, updated_dashboard)
         |> assign(:temp_name, updated_dashboard.name)
         |> assign(:breadcrumb_links, updated_breadcrumbs)
         |> assign(:page_title, updated_page_title)
         |> put_flash(:info, "Settings saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings")}
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
    <div id="dashboard-page-root" class="flex flex-col dark:bg-slate-900 min-h-screen relative" phx-hook="FileDownload">
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
      <iframe name="download_iframe" style="display:none" aria-hidden="true"></iframe>
      <!-- Loading Overlay (covers entire page; message at 1/3 height) -->
      <%= if (@loading_chunks && @loading_progress) || @transponding do %>
        <div class="absolute inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 z-50">
          <div class="absolute left-1/2 -translate-x-1/2" style="top: 33%;">
            <div class="flex flex-col items-center space-y-3">
              <div class="flex items-center space-x-2">
                <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 dark:border-slate-600 border-t-teal-500"></div>
                <span class="text-sm text-gray-600 dark:text-white">
                  <%= if @transponding do %>
                    Transponding data...
                  <% else %>
                    Scientificating piece <%= @loading_progress.current %> of <%= @loading_progress.total %>...
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
                    ></div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      <% end %>
      <div class="w-full">
        <!-- Header -->
        <div class={if(@is_public_access, do: "mb-2", else: "mb-6")}>
          <div class="flex items-center justify-between">
            <!-- Left: Title only -->
            <div class="min-w-0">
              <h1 class="text-2xl font-bold text-gray-900 dark:text-white truncate">
                <%= @dashboard.name %>
              </h1>
            </div>

          <%= if !@print_mode && !@is_public_access && @current_user && @dashboard.user_id == @current_user.id do %>
            <!-- Dashboard owner controls -->
            <div class="flex items-center justify-end gap-3 md:gap-4 flex-nowrap w-auto">
              <% add_btn_id = "dashboard-" <> @dashboard.id <> "-add-widget" %>
              <!-- Add Widget Button -->
              <button id={add_btn_id}
                type="button"
                class="inline-flex items-center whitespace-nowrap rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                title="Add widget"
              >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="-ml-0.5 md:mr-1.5 h-4 w-4">
                  <path fill-rule="evenodd" d="M12 3.75a.75.75 0 01.75.75v6.75h6.75a.75.75 0 010 1.5H12.75v6.75a.75.75 0 01-1.5 0V12.75H4.5a.75.75 0 010-1.5h6.75V4.5a.75.75 0 01.75-.75z" clip-rule="evenodd" />
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
                  <svg class="-ml-0.5 mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                  Cancel
                </button>
              <% else %>
                <.link
                  patch={~p"/app/dashboards/#{@dashboard.id}/edit"}
                  class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg class="md:-ml-0.5 md:mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                  </svg>
                  <span class="hidden md:inline">Edit</span>
                </.link>

                <!-- Configure Button -->
                <.link
                  patch={~p"/app/dashboards/#{@dashboard.id}/configure"}
                  class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                >
                  <svg class="md:-ml-0.5 md:mr-1.5 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  </svg>
                  <span class="hidden md:inline">Configure</span>
                </.link>
                
              <% end %>

              <!-- Status Icon Badges -->
              <div id="status-badges" class="flex items-center gap-2" phx-hook="FastTooltip">
                <!-- Visibility: icon-only (no wrapper), hidden on XS -->
                <%= if @dashboard.visibility do %>
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="hidden sm:inline-block h-5 w-5 text-teal-600 dark:text-teal-400" data-tooltip="Visible to everyone in organization">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
                  </svg>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="hidden sm:inline-block h-5 w-5 text-gray-400 dark:text-slate-500" data-tooltip="Private - only you can see this">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 6a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0ZM4.501 20.118a7.5 7.5 0 0 1 14.998 0A17.933 17.933 0 0 1 12 21.75c-2.676 0-5.216-.584-7.499-1.632Z" />
                  </svg>
                <% end %>

                <!-- Public Link -->
                <%= if @dashboard.access_token do %>
                  <!-- Hidden element with the URL to copy -->
                  <span id="dashboard-public-url" class="hidden"><%= url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}") %></span>

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
                    <svg id="header-link-icon" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z" />
                    </svg>

                    <!-- Check Icon (shown temporarily when copied) -->
                    <svg id="header-check-icon" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-5 w-5 text-green-600 hidden">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                    </svg>
                  </button>
                <% else %>
                  <!-- No token: icon-only (no wrapper), hidden on XS -->
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="hidden sm:inline-block h-5 w-5 text-gray-400 dark:text-slate-500"
                    data-tooltip="No public link available"
                  >
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8.288 15.038a5.25 5.25 0 0 1 7.424 0M5.106 11.856c3.807-3.808 9.98-3.808 13.788 0M1.924 8.674c5.565-5.565 14.587-5.565 20.152 0M12.53 18.22l-.53.53-.53-.53a.75.75 0 0 1 1.06 0Z" />
                  </svg>
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
                    do: "bg-blue-50 dark:bg-blue-900 text-blue-700 dark:text-blue-200 ring-1 ring-inset ring-blue-600/20 dark:ring-blue-500/30",
                    else: "bg-gray-50 dark:bg-gray-900 text-gray-700 dark:text-gray-200 ring-1 ring-inset ring-gray-600/20 dark:ring-gray-500/30"
                  )
                ]}>
                  <%= Trifle.Organizations.Dashboard.visibility_display(@dashboard.visibility) %>
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
          force_granularity_dropdown={@print_mode}
        />
      <% end %>

      <!-- Edit Form (only shown in edit mode for authenticated users) -->
      <%= if !@is_public_access && @live_action == :edit && @dashboard_form do %>
        <div class="mb-6">
          <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-6">
            <h2 class="text-lg font-medium text-gray-900 dark:text-white mb-4">Edit Dashboard</h2>

            <.form
              for={@dashboard_form}
              phx-submit="save_dashboard"
              class="space-y-4"
            >
              <div>
                <label for="dashboard_payload" class="block text-sm font-medium text-gray-700 dark:text-slate-300">Payload</label>
                <textarea
                  name="dashboard[payload]"
                  id="dashboard_payload"
                  rows="10"
                  class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm font-mono"
                  placeholder="JSON configuration for dashboard visualization"
                ><%= if @dashboard.payload, do: Jason.encode!(@dashboard.payload, pretty: true), else: "" %></textarea>
                <%= if @dashboard_changeset && @dashboard_changeset.errors[:payload] do %>
                  <p class="mt-1 text-sm text-red-600 dark:text-red-400">
                    <%= case @dashboard_changeset.errors[:payload] do
                      [{message, _}] -> message
                      [{message, _} | _] -> message
                      message when is_binary(message) -> message
                      _ -> "Invalid payload format"
                    end %>
                  </p>
                <% end %>
                <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">Enter valid JSON configuration for the dashboard visualization</p>
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

      <!-- Grid Layout -->
      <div class="mb-6">
        <div id="dashboard-grid"
             class="grid-stack"
             phx-update="ignore"
             phx-hook="DashboardGrid"
             data-print-mode={if @print_mode, do: "true", else: "false"}
             data-editable={if !@is_public_access && @current_user && @dashboard.user_id == @current_user.id, do: "true", else: "false"}
             data-cols="12"
             data-min-rows="8"
             data-add-btn-id={"dashboard-" <> @dashboard.id <> "-add-widget"}
             data-colors={ChartColors.json_palette()}
             data-initial-grid={Jason.encode!(@dashboard.payload["grid"] || [])}
             data-dashboard-id={@dashboard.id}
             data-public-token={@public_token}>
        </div>
      </div>

      <!-- Configure Modal -->
      <%= if !@is_public_access && @live_action == :configure do %>
        <.app_modal id="configure-modal" show={true} on_cancel={JS.patch(~p"/app/dashboards/#{@dashboard.id}")}>
          <:title>Configure Dashboard</:title>
      <:body>
        <div class="space-y-6">
          <.form for={%{}} phx-submit="save_settings" class="space-y-6">
            <!-- Dashboard Name -->
            <div>
              <label for="configure_name" class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">Dashboard Name</label>
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

            <!-- Database (editable) -->
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">Database</label>
              <div class="grid grid-cols-1 sm:max-w-xs">
                <select name="database_id" class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                  <%= for db <- @databases || [] do %>
                    <option value={db.id} selected={to_string(db.id) == to_string(@database.id)}><%= db.display_name %></option>
                  <% end %>
                </select>
                <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                  <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                </svg>
              </div>
            </div>

            <!-- Dashboard Key -->
            <div>
              <label for="configure_key" class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">Key</label>
              <input
                type="text"
                id="configure_key"
                name="key"
                value={@dashboard.key || ""}
                class="w-full block rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm"
                placeholder="e.g., sales.metrics"
                required
              />
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
                    <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Timeframe</label>
                    <input type="text" name="timeframe" value={@dashboard.default_timeframe || @database.default_timeframe || "24h"} class="mt-2 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm" placeholder="e.g. 24h, 2d, 1w, 1mo, 1y" />
                  </div>
                  <div>
                    <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Granularity</label>
                    <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                      <select name="granularity" class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                        <%= for g <- @available_granularities do %>
                          <option value={g} selected={g == (@dashboard.default_granularity || @database.default_granularity || "1h") }><%= g %></option>
                        <% end %>
                      </select>
                      <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                        <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                      </svg>
                    </div>
                  </div>
                  <div class="sm:col-span-2 flex justify-end">
                    <button type="submit" class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500">Save</button>
                  </div>
                </div>
              </div>
            </.form>
              <!-- Actions -->
              <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                <div class="flex items-center justify-between mb-2">
                  <div>
                    <span class="text-sm font-medium text-gray-700 dark:text-slate-300">Actions</span>
                    <p class="text-xs text-gray-500 dark:text-slate-400">Make a copy of this dashboard.</p>
                  </div>
                  <button
                    type="button"
                    phx-click="duplicate_dashboard"
                    class="inline-flex items-center whitespace-nowrap rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600"
                    title="Duplicate dashboard"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="md:-ml-0.5 md:mr-1.5 h-4 w-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75" />
                    </svg>
                    <span class="hidden md:inline">Duplicate</span>
                  </button>
                </div>
              </div>

              <!-- Visibility Toggle (moved below Actions) -->
              <div class="border-t border-gray-200 dark:border-slate-600 pt-6 flex items-center justify-between">
                <div>
                  <span class="text-sm font-medium text-gray-700 dark:text-slate-300">Visibility</span>
                  <p class="text-xs text-gray-500 dark:text-slate-400">Make this dashboard visible to everyone in the organization</p>
                </div>
                <button
                  type="button"
                  phx-click="toggle_visibility"
                  class={[
                    "relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-teal-600 focus:ring-offset-2",
                    if(@dashboard.visibility, do: "bg-teal-600", else: "bg-gray-200 dark:bg-gray-700")
                  ]}
                >
                  <span class={[
                    "pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out",
                    if(@dashboard.visibility, do: "translate-x-5", else: "translate-x-0")
                  ]}></span>
                </button>
              </div>

              <!-- Public Link Management -->
              <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
                <div class="flex items-center justify-between mb-4">
                  <div>
                    <span class="text-sm font-medium text-gray-700 dark:text-slate-300">Public Link</span>
                    <p class="text-xs text-gray-500 dark:text-slate-400">Allow unauthenticated Read-only access to this dashboard</p>
                  </div>
                </div>

                <%= if @dashboard.access_token do %>
                  <!-- Hidden element with the URL to copy -->
                  <span id="modal-dashboard-public-url" class="hidden"><%= url(@socket, ~p"/d/#{@dashboard.id}?token=#{@dashboard.access_token}") %></span>

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
                      <svg x-show="!copied" class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M15.666 3.888A2.25 2.25 0 0 0 13.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 0 1-.75.75H9a.75.75 0 0 1-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 0 1-2.25 2.25H6.75A2.25 2.25 0 0 1 4.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 0 1 1.927-.184" />
                      </svg>

                      <!-- Check Icon (show when copied) -->
                      <svg x-show="copied" class="-ml-0.5 mr-2 h-4 w-4 text-green-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
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
                      <svg class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
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
                    <svg class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244" />
                    </svg>
                    Generate Public Link
                  </button>
                <% end %>
              </div>

              

              <!-- Danger Zone -->
              <div class="border-t border-red-200 dark:border-red-800 pt-6">
                <div class="mb-4">
                  <span class="text-sm font-medium text-red-700 dark:text-red-400">Danger Zone</span>
                  <p class="text-xs text-red-600 dark:text-red-400">This action cannot be undone</p>
                </div>

                <button
                  type="button"
                  phx-click="delete_dashboard"
                  data-confirm="Are you sure you want to delete this dashboard? This action cannot be undone."
                  class="w-full inline-flex items-center justify-center rounded-md bg-red-50 dark:bg-red-900 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-200 ring-1 ring-inset ring-red-600/20 dark:ring-red-500/30 hover:bg-red-100 dark:hover:bg-red-800"
                  title="Delete this dashboard"
                >
                  <svg class="-ml-0.5 mr-2 h-4 w-4" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                  </svg>
                  Delete Dashboard
                </button>
              </div>
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
                  <label for="widget_type" class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">Widget Type</label>
                  <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                    <select id="widget_type" name="widget_type"
                      class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                      <% sel = (@editing_widget["type"] || "kpi") %>
                      <option value="kpi" selected={sel == "kpi"}>KPI</option>
                      <option value="timeseries" selected={sel == "timeseries"}>Timeseries</option>
                      <option value="category" selected={sel == "category"}>Category</option>
                    </select>
                    <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                      <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                    </svg>
                  </div>
                </div>
              </.form>

              <!-- Widget Title and Options -->
              <.form for={%{}} phx-submit="save_widget" class="space-y-4">
                <input type="hidden" name="widget_id" value={@editing_widget["id"]} />
                <input type="hidden" name="widget_type" value={@editing_widget["type"] || "kpi"} />
                <div>
                  <label for="widget_title" class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">Title</label>
                  <input type="text" id="widget_title" name="widget_title" value={@editing_widget["title"] || ""} class="flex-1 block w-full rounded-md border-gray-300 dark:border-slate-600 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-700 dark:text-white sm:text-sm" placeholder="Widget title" />
                </div>

                <%= case (@editing_widget["type"] || "kpi") do %>
                  <% "kpi" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div class="sm:col-span-2">
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Path</label>
                        <input type="text" name="kpi_path" value={@editing_widget["path"] || ""} class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm" placeholder="e.g. sales.total" />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Function</label>
                        <% fnv = @editing_widget["function"] || "mean" %>
                        <% fnv = if fnv == "avg", do: "mean", else: fnv %>
                        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                          <select name="kpi_function"
                            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                            <option value="max" selected={fnv == "max"}>max</option>
                            <option value="min" selected={fnv == "min"}>min</option>
                            <option value="mean" selected={fnv == "mean"}>mean</option>
                            <option value="sum" selected={fnv == "sum"}>sum</option>
                          </select>
                          <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                            <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                          </svg>
                        </div>
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Size</label>
                        <% sz = @editing_widget["size"] || "m" %>
                        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                          <select name="kpi_size"
                            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                            <option value="s" selected={sz == "s"}>Small</option>
                            <option value="m" selected={sz == "m"}>Medium</option>
                            <option value="l" selected={sz == "l"}>Large</option>
                          </select>
                          <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                            <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                          </svg>
                        </div>
                      </div>
                      <div class="flex items-center gap-4 sm:col-span-2">
                        <% split = @editing_widget["split"] || false %>
                        <% ts = @editing_widget["timeseries"] || false %>
                        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                          <input type="checkbox" name="kpi_split" checked={split} /> Split timeframe by half
                        </label>
                        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                          <input type="checkbox" name="kpi_diff" checked={@editing_widget["diff"] || false} /> Difference between splits
                        </label>
                        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                          <input type="checkbox" name="kpi_timeseries" checked={ts} /> Show timeseries
                        </label>
                      </div>
                      <div class="sm:col-span-2 -mt-2">
                        <p class="text-xs text-gray-500 dark:text-slate-400">
                          Shows percent change between halves: (Now − Prev) / |Prev| × 100. Hidden when Prev is missing or zero.
                        </p>
                      </div>
                    </div>

                  <% "timeseries" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div class="sm:col-span-2">
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Paths (one per line)</label>
                        <% paths = (@editing_widget["paths"] || []) |> Enum.join("\n") %>
                        <textarea name="ts_paths" rows="4" class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm" placeholder="metrics.sales\nmetrics.orders"><%= paths %></textarea>
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Y-axis label</label>
                        <input type="text" name="ts_y_label" value={@editing_widget["y_label"] || ""} class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm" placeholder="e.g., Revenue ($), Orders, Errors (%)" />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Chart Type</label>
                        <% ctype = @editing_widget["chart_type"] || "line" %>
                        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                          <select name="ts_chart_type"
                            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                            <option value="line" selected={ctype == "line"}>Line</option>
                            <option value="area" selected={ctype == "area"}>Area</option>
                            <option value="bar" selected={ctype == "bar"}>Bar</option>
                          </select>
                          <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                            <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
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
                          <input type="checkbox" name="ts_normalized" checked={normalized} /> Normalized
                        </label>
                        <label class="inline-flex items-center gap-2 text-sm text-gray-700 dark:text-slate-300">
                          <input type="checkbox" name="ts_legend" checked={legend} /> Show legend
                        </label>
                      </div>
                    </div>

                  <% "category" -> %>
                    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div class="sm:col-span-2">
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Path</label>
                        <input type="text" name="cat_path" value={@editing_widget["path"] || ""} class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm" placeholder="metrics.category" />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Chart Type</label>
                        <% ctype = @editing_widget["chart_type"] || "bar" %>
                        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
                          <select name="cat_chart_type"
                            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6">
                            <option value="bar" selected={ctype == "bar"}>Bar</option>
                            <option value="pie" selected={ctype == "pie"}>Pie</option>
                            <option value="donut" selected={ctype == "donut"}>Donut</option>
                          </select>
                          <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4">
                            <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                          </svg>
                        </div>
                      </div>
                    </div>
                <% end %>

                <div class="flex items-center justify-end gap-3 pt-2">
                  <button type="button" phx-click="close_widget_editor" class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-3 py-2 text-sm font-semibold text-gray-900 dark:text-white shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600">Cancel</button>
                  <button type="submit" class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600">Save</button>
                </div>
              </.form>

              <!-- Danger Zone -->
              <div class="border-t border-gray-200 dark:border-slate-600 pt-4">
                <h3 class="text-sm font-medium text-red-600 dark:text-red-400">Danger Zone</h3>
                <p class="text-xs text-gray-500 dark:text-slate-400">Delete this widget permanently from the dashboard.</p>
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

        <!-- Dashboard Content -->
        <div class="flex-1 relative">

          <%= if !( @dashboard.payload && map_size(@dashboard.payload) > 0 ) do %>
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
                  <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">Dashboard is empty</h3>
                  <p class="mt-1 text-sm text-gray-500 dark:text-slate-400">
                    This dashboard doesn't have any visualization data yet. Edit the dashboard to add charts and metrics.
                  </p>
                  <%= if !@is_public_access do %>
                    <div class="mt-6">
                      <.link
                        patch={~p"/app/dashboards/#{@dashboard.id}/edit"}
                        class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                      >
                        <svg class="-ml-0.5 mr-1.5 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                        </svg>
                        Edit Dashboard
                      </.link>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <!-- Sticky Summary Footer (only for authenticated users) -->
        <%= if !@is_public_access do %>
          <%= if summary = get_summary_stats(assigns) do %>
          <div class="sticky bottom-0 border-t border-gray-200 dark:border-slate-600 bg-white dark:bg-slate-800 px-4 py-3 shadow-lg z-30">
            <div class="flex flex-wrap items-center gap-4 text-xs">

              <!-- Selected Key -->
              <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 3c2.755 0 5.455.232 8.083.678.533.09.917.556.917 1.096v1.044a2.25 2.25 0 0 1-.659 1.591l-5.432 5.432a2.25 2.25 0 0 0-.659 1.591v2.927a2.25 2.25 0 0 1-1.244 2.013L9.75 21v-6.568a2.25 2.25 0 0 0-.659-1.591L3.659 7.409A2.25 2.25 0 0 1 3 5.818V4.774c0-.54.384-1.006.917-1.096A48.32 48.32 0 0 1 12 3Z" />
                </svg>
                <span class="font-medium">Key:</span>
                <span class="truncate max-w-32" title={summary.key}><%= summary.key %></span>
              </div>

              <!-- Points -->
              <%= if summary.column_count > 0 do %>
                <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                  <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z" />
                  </svg>
                  <span class="font-medium">Points:</span>
                  <span><%= summary.column_count %></span>
                </div>
              <% end %>

              <!-- Paths -->
              <%= if summary.path_count > 0 do %>
                <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                  <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M8.25 6.75h12M8.25 12h12m-12 5.25h12M3.75 6.75h.007v.008H3.75V6.75Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0ZM3.75 12h.007v.008H3.75V12Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm-.375 5.25h.007v.008H3.75v-.008Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z" />
                  </svg>
                  <span class="font-medium">Paths:</span>
                  <span><%= summary.path_count %></span>
                </div>
              <% end %>

              <!-- Transponders -->
              <div class="flex items-center gap-1">
                <svg class="h-4 w-4 text-teal-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m21 7.5-2.25-1.313M21 7.5v2.25m0-2.25-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3 2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75 2.25-1.313M12 21.75V19.5m0 2.25-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25" />
                </svg>
                <span class="font-medium text-gray-700 dark:text-slate-300">Transponders:</span>

                <!-- Success count -->
                <div class="flex items-center gap-1">
                  <svg class="h-3 w-3 text-green-600" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                  </svg>
                  <span class="text-gray-900 dark:text-white"><%= summary.successful_transponders %></span>
                </div>

                <!-- Fail count -->
                <div class="flex items-center gap-1">
                  <svg class="h-3 w-3 text-red-500" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
                  </svg>
                  <%= if summary.failed_transponders > 0 do %>
                    <button
                      phx-click="show_transponder_errors"
                      class="text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 underline"
                    >
                      <%= summary.failed_transponders %>
                    </button>
                  <% else %>
                    <span class="text-gray-900 dark:text-white">0</span>
                  <% end %>
                </div>
              </div>

              <!-- Load Duration -->
              <%= if @load_duration_microseconds do %>
                <div class="flex items-center gap-1 text-gray-600 dark:text-slate-300">
                  <svg class="h-4 w-4 text-teal-500" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m3.75 13.5 10.5-11.25L12 10.5h8.25L9.75 21.75 12 13.5H3.75Z" />
                  </svg>
                  <span class="font-medium">Load:</span>
                  <span><%= format_duration(@load_duration_microseconds) %></span>
                </div>
              <% end %>
              <!-- Export drop-up (right aligned) -->
              <div class="ml-auto relative">
                <button type="button" phx-click="toggle_export_dropdown" class="inline-flex items-center rounded-md bg-white dark:bg-slate-700 px-2.5 py-1.5 text-xs font-medium text-gray-700 dark:text-slate-200 shadow-sm ring-1 ring-inset ring-gray-300 dark:ring-slate-600 hover:bg-gray-50 dark:hover:bg-slate-600">
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-1 text-teal-600 dark:text-teal-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"/></svg>
                  <span class="hidden md:inline">Download</span>
                  <svg class="ml-1 h-3 w-3 text-gray-500 dark:text-slate-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 10.94l3.71-3.71a.75.75 0 011.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd"/></svg>
                </button>
                <%= if @show_export_dropdown do %>
                  <div class="absolute bottom-9 right-0 w-48 bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow-lg py-1 z-40" phx-click-away="hide_export_dropdown">
                    <button type="button" phx-click="download_dashboard_csv" class="w-full text-left px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center">
                      <svg class="h-4 w-4 mr-2 text-teal-600 dark:text-teal-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 16.5V3m0 13.5L8.25 12M12 16.5l3.75-4.5M3 21h18"/></svg>
                      CSV (table)
                    </button>
                    <button type="button" phx-click="download_dashboard_json" class="w-full text-left px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700 flex items-center">
                      <svg class="h-4 w-4 mr-2 text-indigo-600 dark:text-indigo-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M12 16.5V3m0 13.5L8.25 12M12 16.5l3.75-4.5M3 21h18"/></svg>
                      JSON (raw)
                    </button>
                    <a href={~p"/app/export/dashboards/#{@dashboard.id}/pdf"} target="download_iframe" class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700">
                      <span class="flex items-center">
                        <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 mr-2 text-rose-600 dark:text-rose-400" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"/></svg>
                        PDF (print)
                      </span>
                    </a>
                    <a href={~p"/app/export/dashboards/#{@dashboard.id}/png"} target="download_iframe" class="w-full block px-3 py-2 text-xs text-gray-700 dark:text-slate-200 hover:bg-gray-100 dark:hover:bg-slate-700">
                      <span class="flex items-center">
                        <svg class="h-4 w-4 mr-2 text-amber-600 dark:text-amber-400" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"/></svg>
                        PNG (image)
                      </span>
                    </a>
                  </div>
                <% end %>
              </div>
            </div>
          </div>

        <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp key_matches_pattern?(key, pattern) do
    cond do
      String.contains?(pattern, "^") or String.contains?(pattern, "$") ->
        case Regex.compile(pattern) do
          {:ok, regex} -> Regex.match?(regex, key)
          {:error, _} -> false
        end
      true ->
        key == pattern
    end
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
    if socket.assigns.is_public_access do
      ~p"/d/#{socket.assigns.dashboard.id}?#{params}&token=#{socket.assigns.public_token}"
    else
      ~p"/app/dashboards/#{socket.assigns.dashboard.id}?#{params}"
    end
  end

  defp navigate_timeframe(socket, direction) do
    from = socket.assigns.from
    to = socket.assigns.to

    duration_seconds = DateTime.diff(to, from, :second)

    {new_from, new_to} = case direction do
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
end
