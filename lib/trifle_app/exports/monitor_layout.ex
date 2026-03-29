defmodule TrifleApp.Exports.MonitorLayout do
  @moduledoc """
  Builds export layouts for Monitors (report and alert) so they can be rendered
  via the shared Chrome exporter pipeline.
  """

  alias Trifle.Monitors
  alias Trifle.Monitors.{Alert, AlertSeries, Monitor}
  alias Trifle.Monitors.AlertEvaluator
  alias Trifle.Monitors.AlertEvaluator.Utils, as: AlertEvaluatorUtils
  alias Trifle.Organizations
  alias Trifle.Organizations.DashboardSegments
  alias Trifle.Stats.{Series, Source}
  alias Trifle.Stats.Nocturnal
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Exports.Series, as: SeriesExport

  alias TrifleApp.Components.DashboardWidgets.{LayoutTree, WidgetData, WidgetView}
  alias TrifleApp.Exports.Layout
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing

  @default_viewport %{width: 1366, height: 900}
  @widget_viewport %{width: 1024, height: 768}

  @doc """
  Returns the normalized grid widget definitions for an alert monitor.
  """
  @spec alert_widgets(Monitor.t(), Series.t() | nil) :: list()
  def alert_widgets(%Monitor{} = monitor, stats \\ nil) do
    source_widget = AlertSeries.source_widget(monitor)
    groups = alert_widget_groups(monitor, stats)
    [source_widget | groups]
  end

  @doc """
  Builds the synthetic alert preview dashboard used by monitor pages and exports.
  """
  @spec alert_dashboard(Monitor.t(), Series.t() | nil) :: map()
  def alert_dashboard(%Monitor{} = monitor, stats \\ nil) do
    %{
      id: "#{monitor.id}-alert-preview",
      key: monitor.alert_metric_key,
      name: monitor.name || "Alert Preview",
      payload: %{"grid" => alert_widgets(monitor, stats)}
    }
  end

  @doc """
  Builds an export layout for the provided monitor struct.
  """
  @spec build(Monitor.t(), Keyword.t()) :: {:ok, Layout.t()} | {:error, term()}
  def build(%Monitor{} = monitor, opts \\ []) do
    do_build(monitor, opts)
  end

  @doc """
  Builds a layout for a single widget within the monitor's insights dashboard.
  """
  @spec build_widget(Monitor.t(), String.t(), Keyword.t()) ::
          {:ok, Layout.t()} | {:error, term()}
  def build_widget(%Monitor{} = monitor, widget_id, opts \\ []) do
    opts = Keyword.put(opts, :selected_widget_id, widget_id)
    do_build(monitor, opts)
  end

  @doc """
  Resolves the monitor dataset for CSV/JSON exports using the same parameter pipeline.
  """
  @spec series_export(Monitor.t(), Keyword.t()) ::
          {:ok, %{export: SeriesExport.result(), timeframe: map()}} | {:error, term()}
  def series_export(%Monitor{} = monitor, opts \\ []) do
    with {:ok, context} <- build_context(monitor, opts) do
      {:ok, %{export: context.export, timeframe: context.timeframe}}
    end
  end

  defp do_build(monitor, opts) do
    with {:ok, context} <- build_context(monitor, opts),
         {:ok, layout} <-
           compose_layout(
             monitor,
             context.export,
             context.timeframe,
             context.theme,
             context.viewport,
             context.source,
             context.selected_widget_id
           ) do
      {:ok, layout}
    end
  end

  defp build_context(monitor, opts) do
    params = Keyword.get(opts, :params, %{})
    theme = Keyword.get(opts, :theme, :light)
    selected_widget = Keyword.get(opts, :selected_widget_id)

    default_viewport =
      case selected_widget do
        nil -> @default_viewport
        _ -> @widget_viewport
      end

    viewport = Keyword.get(opts, :viewport, default_viewport)

    with {:ok, source} <- resolve_source(monitor),
         {:ok, config} <- {:ok, Source.stats_config(source)},
         granularities <- Source.available_granularities(source) || [],
         defaults <- monitor_defaults(monitor, source, config, granularities),
         {:ok, timeframe} <-
           resolve_timeframe(params, config, granularities, defaults, monitor),
         {:ok, export} <-
           SeriesExport.fetch(
             source,
             timeframe.key,
             timeframe.from,
             timeframe.to,
             timeframe.granularity,
             progress_callback: nil
           ) do
      {:ok,
       %{
         export: export,
         timeframe: timeframe,
         theme: theme,
         viewport: viewport,
         source: source,
         selected_widget_id: selected_widget
       }}
    end
  end

  defp resolve_source(%Monitor{source_type: :database, source_id: id}) when is_binary(id) do
    try do
      {:ok, Organizations.get_database!(id) |> Source.from_database()}
    rescue
      Ecto.NoResultsError -> {:error, :source_not_found}
    end
  end

  defp resolve_source(%Monitor{source_type: :project, source_id: id, organization_id: org_id})
       when is_binary(id) do
    try do
      {:ok, Organizations.get_project_for_org!(org_id, id) |> Source.from_project()}
    rescue
      Ecto.NoResultsError -> {:error, :source_not_found}
    end
  end

  defp resolve_source(_monitor), do: {:error, :source_not_configured}

  defp monitor_defaults(%Monitor{type: :report} = monitor, source, config, granularities) do
    report_timeframe_defaults(monitor, source, config, granularities)
  end

  defp monitor_defaults(%Monitor{type: :alert} = monitor, source, config, granularities) do
    alert_timeframe_defaults(monitor, source, config, granularities)
  end

  defp monitor_defaults(_monitor, _source, config, _granularities) do
    case parse_timeframe_range("24h", config) do
      {:ok, from, to} ->
        %{from: from, to: to, granularity: "1h", timeframe: "24h", use_fixed: false}

      :error ->
        %{from: nil, to: nil, granularity: "1h", timeframe: "24h", use_fixed: false}
    end
  end

  defp report_timeframe_defaults(%Monitor{} = monitor, source, config, granularities) do
    settings = monitor.report_settings || %{}
    frequency = Map.get(settings, :frequency, :weekly)
    timeframe_input = resolve_report_timeframe(settings.timeframe, frequency, source)

    {from, to} =
      case compute_report_time_range(monitor, timeframe_input, config) do
        {:ok, from, to} -> {from, to}
        :error -> fallback_range(config)
      end

    fallback_granularity =
      case source do
        nil -> nil
        src -> Source.default_granularity(src)
      end

    granularity = normalize_granularity(settings.granularity, granularities, fallback_granularity)

    %{
      from: from,
      to: to,
      granularity: granularity,
      timeframe: timeframe_input,
      use_fixed: false
    }
  end

  defp resolve_report_timeframe(timeframe, frequency, source) do
    cond do
      is_binary(timeframe) and String.trim(timeframe) != "" ->
        timeframe

      frequency == :hourly ->
        "1h"

      frequency == :daily ->
        "1d"

      frequency == :weekly ->
        "7d"

      frequency == :monthly ->
        "1mo"

      source ->
        Source.default_timeframe(source) || "24h"

      true ->
        "24h"
    end
  end

  defp alert_timeframe_defaults(%Monitor{} = monitor, source, config, granularities) do
    evaluation_timeframe =
      monitor.alert_timeframe || Source.default_timeframe(source) || "1h"

    display_timeframe = multiply_timeframe(evaluation_timeframe, 4)

    {from, to} =
      case parse_timeframe_range(display_timeframe, config) do
        {:ok, from, to} -> {from, to}
        :error -> fallback_range(config)
      end

    fallback_granularity =
      monitor.alert_granularity ||
        case source do
          nil -> nil
          src -> Source.default_granularity(src)
        end

    granularity =
      normalize_granularity(monitor.alert_granularity, granularities, fallback_granularity)

    %{
      from: from,
      to: to,
      granularity: granularity,
      timeframe: display_timeframe,
      use_fixed: false
    }
  end

  defp fallback_range(config) do
    case parse_timeframe_range("24h", config) do
      {:ok, from, to} -> {from, to}
      :error -> {nil, nil}
    end
  end

  defp multiply_timeframe(timeframe, multiplier) when is_binary(timeframe) and multiplier >= 1 do
    parser = Parser.new(timeframe)

    if Parser.valid?(parser) do
      offset = parser.offset * multiplier
      "#{offset}#{timeframe_unit_suffix(parser.unit)}"
    else
      timeframe
    end
  end

  defp multiply_timeframe(_timeframe, _multiplier), do: "24h"

  defp timeframe_unit_suffix(:second), do: "s"
  defp timeframe_unit_suffix(:minute), do: "m"
  defp timeframe_unit_suffix(:hour), do: "h"
  defp timeframe_unit_suffix(:day), do: "d"
  defp timeframe_unit_suffix(:week), do: "w"
  defp timeframe_unit_suffix(:month), do: "mo"
  defp timeframe_unit_suffix(:quarter), do: "q"
  defp timeframe_unit_suffix(:year), do: "y"
  defp timeframe_unit_suffix(_), do: ""

  defp normalize_granularity(value, available, fallback) do
    cond do
      is_binary(value) and value in available -> value
      is_binary(fallback) and fallback in available -> fallback
      available != [] -> hd(available)
      true -> value
    end
  end

  defp resolve_timeframe(params, config, available_granularities, defaults, monitor) do
    defaults_map = %{
      default_timeframe: defaults.timeframe,
      default_granularity: defaults.granularity
    }

    {from, to, granularity, smart, use_fixed_display} =
      UrlParsing.parse_url_params(
        params,
        config,
        available_granularities,
        defaults_map
      )

    display =
      case {from, to} do
        {nil, nil} -> defaults.timeframe
        {from, to} -> TimeframeParsing.format_timeframe_display(from, to)
      end

    {:ok,
     %{
       from: from || defaults.from,
       to: to || defaults.to,
       granularity: granularity || defaults.granularity,
       smart: smart || defaults.timeframe,
       use_fixed: use_fixed_display || defaults.use_fixed,
       display: display,
       key: resolved_key_from_params(monitor, params)
     }}
  end

  defp resolved_key_from_params(%Monitor{} = monitor, params) do
    case Map.get(params, "key") do
      key when is_binary(key) and key != "" ->
        key

      _ ->
        case monitor.type do
          :report -> resolved_report_key(monitor, params)
          :alert -> monitor.alert_metric_key
          _ -> nil
        end
    end
  end

  defp resolved_report_key(%Monitor{} = monitor, params) do
    with %{} = dashboard <- monitor_dashboard_struct(monitor),
         key when is_binary(key) <- Map.get(dashboard, :key) || Map.get(dashboard, "key") do
      segments = dashboard_segments(dashboard)

      overrides =
        case Map.get(params, "segments") do
          %{} = map -> DashboardSegments.normalize_value_map(map)
          _ -> DashboardSegments.normalize_value_map(monitor.segment_values || %{})
        end

      {segment_values, segments_with_current} =
        DashboardSegments.compute_state(segments, overrides, %{})

      DashboardSegments.resolve_key(key, segments_with_current, segment_values)
    else
      _ ->
        monitor.dashboard && monitor.dashboard.key
    end
  end

  defp monitor_dashboard_struct(%Monitor{dashboard: %Ecto.Association.NotLoaded{}}), do: nil
  defp monitor_dashboard_struct(%Monitor{dashboard: nil}), do: nil
  defp monitor_dashboard_struct(%Monitor{dashboard: dashboard}), do: dashboard

  defp dashboard_segments(dashboard) do
    dashboard
    |> Map.get(:segments)
    |> case do
      nil -> Map.get(dashboard, "segments")
      value -> value
    end
    |> case do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp compose_layout(monitor, export, timeframe, theme, viewport, source, selected_widget_id) do
    stats_struct = export.raw.series
    dashboard = insights_dashboard(monitor, stats_struct)
    root_items_all = WidgetView.root_grid_items(dashboard)
    grid_items = maybe_filter_widgets(root_items_all, selected_widget_id)
    widget_items = LayoutTree.flatten_widgets(grid_items)

    cond do
      grid_items == [] and selected_widget_id ->
        {:error, :widget_not_found}

      grid_items == [] ->
        {:error, :no_widgets}

      true ->
        datasets =
          WidgetData.datasets_from_dashboard(stats_struct, dashboard)
          |> WidgetData.dataset_maps()
          |> maybe_prune_dataset_maps(Enum.map(widget_items, &widget_id/1))

        {datasets, _alert_evaluations} =
          inject_alert_overlay(datasets, monitor, stats_struct)

        render_assigns =
          %{
            dashboard: %{
              dashboard
              | payload: Map.put(dashboard.payload || %{}, "grid", grid_items)
            },
            stats: stats_struct,
            current_user: nil,
            can_edit_dashboard: false,
            can_clone_dashboard: false,
            can_manage_dashboard: false,
            can_manage_lock: false,
            is_public_access: true,
            print_mode: true,
            kpi_values: datasets.kpi_values,
            kpi_visuals: datasets.kpi_visuals,
            timeseries: datasets.timeseries,
            category: datasets.category,
            table: datasets.table,
            text_widgets: datasets.text,
            list: datasets.list,
            distribution: datasets.distribution,
            export_params: %{},
            dashboard_id: Map.get(dashboard, :id) || Map.get(dashboard, "id"),
            print_width: printable_width(viewport),
            print_cell_height: widget_print_cell_height(grid_items, selected_widget_id, viewport),
            transponder_info: %{}
          }

        layout =
          Layout.new(%{
            id: monitor.id,
            kind: if(selected_widget_id, do: :monitor_widget, else: :monitor),
            title: monitor.name,
            theme: theme,
            viewport: viewport,
            assigns: %{theme_class: theme_class(theme)}
          })
          |> Layout.put_meta(:monitor, %{id: monitor.id, type: monitor.type})
          |> Layout.put_meta(:source, %{id: Source.id(source), type: Source.type(source)})
          |> Layout.put_meta(:timeframe, %{
            display: timeframe.display,
            from: timeframe.from,
            to: timeframe.to,
            granularity: timeframe.granularity,
            smart: timeframe.smart,
            use_fixed: timeframe.use_fixed
          })
          |> Layout.put_meta(:key, timeframe.key)
          |> maybe_put_widget_meta(selected_widget_id)
          |> Layout.with_render(WidgetView, :grid, render_assigns)

        {:ok, layout}
    end
  end

  defp theme_class(:dark), do: "dark"
  defp theme_class(_), do: nil

  defp insights_dashboard(%Monitor{type: :report, dashboard: %{} = dashboard}, _stats),
    do: dashboard

  defp insights_dashboard(%Monitor{type: :alert} = monitor, stats) do
    alert_dashboard(monitor, stats)
  end

  defp insights_dashboard(%Monitor{} = monitor, _stats) do
    %{
      id: "#{monitor.id}-preview",
      key: nil,
      name: monitor.name || "Monitor Preview",
      payload: %{"grid" => []}
    }
  end

  defp maybe_filter_widgets(items, nil), do: items

  defp maybe_filter_widgets(items, widget_id) do
    case LayoutTree.find_node(items, widget_id) do
      nil -> []
      item -> normalize_single_widget_layout([item])
    end
  end

  defp maybe_prune_dataset_maps(datasets, widget_ids) do
    Map.new(datasets, fn {key, map} ->
      pruned =
        map
        |> Enum.filter(fn {id, _} -> id in widget_ids end)
        |> Enum.into(%{})

      {key, pruned}
    end)
  end

  defp widget_id(%{"id" => id}), do: to_string(id)
  defp widget_id(%{id: id}), do: to_string(id)
  defp widget_id(_), do: nil

  defp normalize_single_widget_layout([item]) do
    item =
      item
      |> ensure_string_keys()
      |> Map.put("x", 0)
      |> Map.put("y", 0)
      |> Map.put("w", 12)

    base_height = derive_widget_height(item)
    enforced_height = max(base_height, 12)

    item =
      item
      |> Map.put("h", enforced_height)
      |> expand_tab_children(enforced_height)

    [item]
  end

  defp normalize_single_widget_layout(items), do: items

  defp ensure_string_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      string_key =
        cond do
          is_binary(key) -> key
          is_atom(key) -> Atom.to_string(key)
          true -> to_string(key)
        end

      normalized_value =
        cond do
          is_map(value) -> ensure_string_keys(value)
          is_list(value) -> Enum.map(value, &ensure_string_keys/1)
          true -> value
        end

      Map.put(acc, string_key, normalized_value)
    end)
  end

  defp ensure_string_keys(other), do: other

  defp derive_widget_height(%{"h" => height}) when is_integer(height) and height > 0, do: height

  defp derive_widget_height(%{"tabs" => %{"widgets" => widgets}}) when is_list(widgets) do
    widgets
    |> Enum.map(&derive_widget_height/1)
    |> Enum.max(fn -> 6 end)
  end

  defp derive_widget_height(_), do: 6

  defp expand_tab_children(%{"tabs" => %{"widgets" => widgets} = tabs} = widget, height) do
    expanded_widgets =
      widgets
      |> Enum.map(&ensure_string_keys/1)
      |> Enum.map(fn child ->
        child
        |> Map.put("x", 0)
        |> Map.put("y", 0)
        |> Map.put("w", 12)
        |> Map.put("h", height)
        |> expand_tab_children(height)
      end)

    updated_tabs = Map.put(tabs, "widgets", expanded_widgets)

    widget
    |> Map.put("tabs", updated_tabs)
    |> Map.put("h", height)
  end

  defp expand_tab_children(widget, _height), do: widget

  defp maybe_put_widget_meta(layout, nil), do: layout

  defp maybe_put_widget_meta(layout, widget_id) do
    Layout.put_meta(layout, :widget, %{id: widget_id})
  end

  defp printable_width(%{width: width}) when is_integer(width) and width > 0 do
    min(width, 1366)
  end

  defp printable_width(_), do: 1366

  defp widget_print_cell_height(_grid, nil, _viewport), do: nil

  defp widget_print_cell_height(grid, _widget_id, %{height: height})
       when is_list(grid) and is_integer(height) and height > 0 do
    rows =
      grid
      |> Enum.map(&derive_widget_height/1)
      |> Enum.max(fn -> 0 end)

    cond do
      rows <= 0 -> nil
      true -> max(div(height, rows), 40)
    end
  end

  defp widget_print_cell_height(_, _, _), do: nil

  defp monitor_alerts(%Monitor{} = monitor), do: Monitors.sort_alerts(monitor.alerts)
  defp monitor_alerts(_), do: []

  @spec alert_widget_id(Monitor.t(), Alert.t()) :: String.t() | nil
  def alert_widget_id(%Monitor{id: monitor_id}, %Alert{id: alert_id})
      when not is_nil(monitor_id) and not is_nil(alert_id) do
    "#{monitor_id}-alert-#{alert_id}-chart"
  end

  def alert_widget_id(_, _), do: nil

  @spec alert_label(Alert.t()) :: String.t()
  def alert_label(%Alert{} = alert) do
    label = humanize_analysis_strategy(alert.analysis_strategy || :threshold)

    case alert_configuration_summary(alert) do
      nil -> label
      summary -> "#{label} · #{summary}"
    end
  end

  def inject_alert_overlay(datasets, %Monitor{} = monitor, %Series{} = stats) do
    {dataset_overrides, evaluations} = build_alert_overlay_map(monitor, stats)

    updated_timeseries =
      Enum.reduce(dataset_overrides, Map.get(datasets, :timeseries, %{}), fn {widget_id, extras},
                                                                             acc ->
        Map.update(acc, widget_id, extras, &Map.merge(&1, extras))
      end)

    datasets =
      datasets
      |> Map.put(:timeseries, updated_timeseries)

    {datasets, evaluations}
  end

  def inject_alert_overlay(datasets, _monitor, _stats), do: {datasets, %{}}

  defp build_alert_overlay_map(%Monitor{} = monitor, %Series{} = stats) do
    alerts = monitor_alerts(monitor)
    targets = AlertSeries.resolved_final_targets(stats, monitor)

    {dataset_map, evaluation_acc} =
      Enum.reduce(targets, {%{}, %{}}, fn target, {dataset_acc, eval_acc} ->
        Enum.reduce(alerts, {dataset_acc, eval_acc}, fn
          %Alert{id: nil}, acc ->
            acc

          %Alert{} = alert, {dataset_inner, eval_inner} ->
            widget_id = alert_target_widget_id(monitor, target, alert)

            case AlertEvaluator.evaluate_points(alert, target.source_path, target.points) do
              {:ok, result} ->
                overlay = AlertEvaluator.overlay(result)

                dataset =
                  build_alert_widget_dataset(
                    widget_id,
                    alert,
                    target,
                    %{
                      alert_overlay: overlay,
                      alert_baseline_series: Map.get(overlay, :baseline_series, []),
                      alert_triggered: result.triggered?,
                      alert_summary: result.summary,
                      alert_meta:
                        Map.merge(result.meta || %{}, %{
                          series_name: target.name,
                          series_source_path: target.source_path
                        }),
                      alert_ref: to_string(alert.id),
                      alert_strategy:
                        alert.analysis_strategy |> Kernel.||(:threshold) |> to_string()
                    }
                  )

                {
                  Map.put(dataset_inner, widget_id, dataset),
                  Map.update(
                    eval_inner,
                    alert.id,
                    [%{target: target, result: result}],
                    fn existing ->
                      existing ++ [%{target: target, result: result}]
                    end
                  )
                }

              {:error, reason} ->
                dataset =
                  build_alert_widget_dataset(
                    widget_id,
                    alert,
                    target,
                    %{
                      alert_overlay: nil,
                      alert_baseline_series: [],
                      alert_triggered: false,
                      alert_summary: "Alert evaluation failed: #{inspect(reason)}",
                      alert_meta: %{
                        error: reason,
                        series_name: target.name,
                        series_source_path: target.source_path
                      },
                      alert_ref: to_string(alert.id),
                      alert_strategy:
                        alert.analysis_strategy |> Kernel.||(:threshold) |> to_string()
                    }
                  )

                {
                  Map.put(dataset_inner, widget_id, dataset),
                  Map.update(
                    eval_inner,
                    alert.id,
                    [%{target: target, error: reason}],
                    fn existing ->
                      existing ++ [%{target: target, error: reason}]
                    end
                  )
                }
            end
        end)
      end)

    evaluations =
      Enum.into(evaluation_acc, %{}, fn {alert_id, results} ->
        alert = Enum.find(alerts, &(&1.id == alert_id))
        {alert_id, aggregate_alert_results(alert, results)}
      end)

    {dataset_map, evaluations}
  end

  defp alert_widget_groups(%Monitor{} = monitor, %Series{} = stats) do
    alerts = monitor_alerts(monitor)
    targets = AlertSeries.resolved_final_targets(stats, monitor)
    base_y = AlertSeries.source_widget_height()

    if alerts == [] do
      []
    else
      targets
      |> Enum.with_index()
      |> Enum.map(fn {target, index} ->
        group_height = alert_group_height(length(alerts))

        %{
          "id" => alert_group_id(monitor, target),
          "type" => "group",
          "title" => target.name,
          "w" => 12,
          "h" => group_height,
          "x" => 0,
          "y" => base_y + index * group_height,
          "children" => alert_group_widgets(monitor, target, alerts)
        }
      end)
    end
  end

  defp alert_widget_groups(_monitor, _stats), do: []

  defp alert_group_widgets(%Monitor{} = monitor, target, alerts) do
    alerts
    |> Enum.reject(&is_nil(&1.id))
    |> Enum.with_index()
    |> Enum.map(fn {alert, index} ->
      %{
        "id" => alert_target_widget_id(monitor, target, alert),
        "type" => "timeseries",
        "title" => alert_label(alert),
        "chart_type" => "line",
        "legend" => false,
        "stacked" => false,
        "normalized" => false,
        "w" => 12,
        "h" => alert_chart_height(),
        "x" => 0,
        "y" => index * alert_chart_height(),
        "alert_ref" => to_string(alert.id),
        "alert_strategy" => alert.analysis_strategy |> Kernel.||(:threshold) |> to_string()
      }
    end)
  end

  defp build_alert_widget_dataset(widget_id, alert, target, extras) do
    Map.merge(
      %{
        id: widget_id,
        chart_type: "line",
        stacked: false,
        normalized: false,
        legend: false,
        y_label: target.name,
        hovered_only: false,
        series: [
          %{
            name: target.name,
            data: target.data,
            color: target.color,
            source_path: target.source_path
          }
        ],
        alert_ref: to_string(alert.id),
        alert_strategy: alert.analysis_strategy |> Kernel.||(:threshold) |> to_string()
      },
      extras
    )
  end

  defp aggregate_alert_results(%Alert{} = alert, results) do
    AlertEvaluatorUtils.build_series_aggregation(
      results,
      alert_id: alert && alert.id,
      strategy: alert && (alert.analysis_strategy || :threshold)
    )
  end

  defp alert_group_id(%Monitor{id: monitor_id}, target) do
    "#{monitor_id}-alert-series-#{target.index}-group"
  end

  defp alert_target_widget_id(%Monitor{id: monitor_id}, target, %Alert{id: alert_id}) do
    "#{monitor_id}-alert-series-#{target.index}-alert-#{alert_id}-chart"
  end

  defp alert_chart_height, do: 5

  defp alert_group_height(alert_count) when alert_count > 0,
    do: alert_count * alert_chart_height()

  defp alert_group_height(_alert_count), do: alert_chart_height()

  defp compute_report_time_range(%Monitor{} = monitor, timeframe_input, config) do
    settings = monitor.report_settings || %{}
    frequency = Map.get(settings, :frequency)
    now = timezone_now(config)

    cond do
      frequency == :hourly ->
        from = floor_time(now, 1, :hour, config)
        {:ok, from, now}

      frequency == :daily ->
        from = floor_time(now, 1, :day, config)
        {:ok, from, now}

      frequency == :weekly ->
        from = floor_time(now, 1, :week, config)
        {:ok, from, now}

      frequency == :monthly ->
        from = floor_time(now, 1, :month, config)
        {:ok, from, now}

      true ->
        parse_timeframe_range(timeframe_input, config)
    end
  end

  defp humanize_analysis_strategy(nil), do: "Threshold"
  defp humanize_analysis_strategy(:threshold), do: "Threshold"
  defp humanize_analysis_strategy(:range), do: "Range"
  defp humanize_analysis_strategy(:hampel), do: "Hampel (Robust Outlier)"
  defp humanize_analysis_strategy(:cusum), do: "CUSUM (Level Shift)"

  defp humanize_analysis_strategy(strategy) when is_atom(strategy) do
    strategy
    |> Atom.to_string()
    |> humanize_analysis_strategy()
  end

  defp humanize_analysis_strategy(strategy) when is_binary(strategy) do
    strategy
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_analysis_strategy(_), do: "Threshold"

  defp alert_configuration_summary(%Alert{} = alert) do
    case {alert.analysis_strategy || :threshold, alert.settings} do
      {:threshold, %Alert.Settings{} = settings} ->
        case settings.threshold_value do
          value when is_number(value) ->
            comparator =
              case settings.threshold_direction || :above do
                :below -> "≤"
                _ -> "≥"
              end

            "𝑥 #{comparator} #{format_number(value)}"

          _ ->
            nil
        end

      {:range, %Alert.Settings{} = settings} ->
        min_value = settings.range_min_value
        max_value = settings.range_max_value

        if is_number(min_value) and is_number(max_value) do
          "#{format_number(min_value)} ≤ 𝑥 ≤ #{format_number(max_value)}"
        else
          nil
        end

      {:hampel, %Alert.Settings{} = settings} ->
        ["𝑤", "𝑘", "𝑚"]
        |> Enum.zip([
          settings.hampel_window_size,
          settings.hampel_k,
          settings.hampel_mad_floor
        ])
        |> Enum.map(fn {label, value} -> format_pair(label, value) end)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          parts -> Enum.join(parts, ", ")
        end

      {:cusum, %Alert.Settings{} = settings} ->
        ["𝑘", "𝐻"]
        |> Enum.zip([settings.cusum_k, settings.cusum_h])
        |> Enum.map(fn {label, value} -> format_pair(label, value) end)
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          parts -> Enum.join(parts, ", ")
        end

      _ ->
        nil
    end
  end

  defp format_pair(_label, value) when not is_number(value), do: nil
  defp format_pair(label, value), do: "#{label}=#{format_number(value)}"

  defp format_number(nil), do: nil
  defp format_number(value) when is_integer(value), do: Integer.to_string(value)

  defp format_number(value) when is_float(value) do
    value
    |> Float.round(6)
    |> :erlang.float_to_binary(decimals: 6)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  defp format_number(value) when is_binary(value), do: value
  defp format_number(value), do: to_string(value)

  defp parse_timeframe_range(timeframe_input, config) do
    case TimeframeParsing.parse_smart_timeframe(timeframe_input || "24h", config) do
      {:ok, from, to, _smart, _fixed} ->
        {:ok, from, to}

      {:error, _reason} ->
        case TimeframeParsing.parse_smart_timeframe("24h", config) do
          {:ok, from, to, _smart, _fixed} -> {:ok, from, to}
          _ -> :error
        end
    end
  end

  defp timezone_now(config) do
    DateTime.utc_now()
    |> DateTime.shift_zone!(config.time_zone || "UTC")
  end

  defp floor_time(datetime, offset, unit, config) do
    datetime
    |> Nocturnal.new(config)
    |> Nocturnal.floor(offset, unit)
  end
end
