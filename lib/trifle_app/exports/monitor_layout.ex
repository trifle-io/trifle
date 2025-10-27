defmodule TrifleApp.Exports.MonitorLayout do
  @moduledoc """
  Builds export layouts for Monitors (report and alert) so they can be rendered
  via the shared Chrome exporter pipeline.
  """

  alias Ecto.NoResultsError
  alias Trifle.Monitors.Monitor
  alias Trifle.Organizations
  alias Trifle.Stats.Source
  alias Trifle.Stats.Nocturnal
  alias Trifle.Stats.Nocturnal.Parser
  alias Trifle.Exports.Series, as: SeriesExport

  alias TrifleApp.Components.DashboardWidgets.{WidgetData, WidgetView}
  alias TrifleApp.Exports.Layout
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing

  @default_viewport %{width: 1366, height: 900}

  @doc """
  Returns the normalized grid widget definitions for an alert monitor.
  """
  @spec alert_widgets(Monitor.t()) :: list()
  def alert_widgets(%Monitor{} = monitor) do
    monitor_alert_widgets(monitor) || []
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

  defp do_build(monitor, opts) do
    params = Keyword.get(opts, :params, %{})
    theme = Keyword.get(opts, :theme, :light)
    viewport = Keyword.get(opts, :viewport, @default_viewport)
    selected_widget = Keyword.get(opts, :selected_widget_id)

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
           ),
         {:ok, layout} <-
           compose_layout(
             monitor,
             export,
             timeframe,
             theme,
             viewport,
             source,
             selected_widget
           ) do
      {:ok, layout}
    end
  end

  defp resolve_source(%Monitor{source_type: :database, source_id: id}) when is_binary(id) do
    try do
      {:ok, Organizations.get_database!(id) |> Source.from_database()}
    rescue
      Ecto.NoResultsError -> {:error, :source_not_found}
    end
  end

  defp resolve_source(%Monitor{source_type: :project, source_id: id}) when is_binary(id) do
    try do
      {:ok, Organizations.get_project!(id) |> Source.from_project()}
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
          :report -> monitor.dashboard && monitor.dashboard.key
          :alert -> monitor.alert_metric_key
          _ -> nil
        end
    end
  end

  defp compose_layout(monitor, export, timeframe, theme, viewport, source, selected_widget_id) do
    stats_struct = export.raw.series
    dashboard = insights_dashboard(monitor)
    grid_items_all = WidgetView.grid_items(dashboard)
    grid_items = maybe_filter_widgets(grid_items_all, selected_widget_id)

    cond do
      grid_items == [] and selected_widget_id ->
        {:error, :widget_not_found}

      grid_items == [] ->
        {:error, :no_widgets}

      true ->
        datasets =
          WidgetData.datasets_from_dashboard(stats_struct, dashboard)
          |> WidgetData.dataset_maps()
          |> maybe_prune_dataset_maps(Enum.map(grid_items, &widget_id/1))

        render_assigns =
          %{
            dashboard: %{
              dashboard
              | payload: Map.put(dashboard.payload || %{}, "grid", grid_items)
            },
            stats: stats_struct,
            current_user: nil,
            can_edit_dashboard: false,
            is_public_access: true,
            print_mode: true,
            kpi_values: datasets.kpi_values,
            kpi_visuals: datasets.kpi_visuals,
            timeseries: datasets.timeseries,
            category: datasets.category,
            text_widgets: datasets.text,
            export_params: %{},
            dashboard_id: Map.get(dashboard, :id) || Map.get(dashboard, "id")
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

  defp insights_dashboard(%Monitor{type: :report, dashboard: %{} = dashboard}), do: dashboard

  defp insights_dashboard(%Monitor{type: :alert} = monitor) do
    metric_path =
      monitor.alert_metric_path
      |> to_string()
      |> String.trim()

    widgets =
      case monitor_alert_widgets(monitor) do
        nil -> build_default_alert_widgets(monitor, metric_path)
        [] -> []
        list -> list
      end

    %{
      id: "#{monitor.id}-alert-preview",
      key: monitor.alert_metric_key,
      name: monitor.name || "Alert Preview",
      payload: %{"grid" => widgets}
    }
  end

  defp insights_dashboard(%Monitor{} = monitor) do
    %{
      id: "#{monitor.id}-preview",
      key: nil,
      name: monitor.name || "Monitor Preview",
      payload: %{"grid" => []}
    }
  end

  defp maybe_filter_widgets(items, nil), do: items

  defp maybe_filter_widgets(items, widget_id) do
    Enum.filter(items, fn item -> widget_id(item) == widget_id end)
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

  defp maybe_put_widget_meta(layout, nil), do: layout

  defp maybe_put_widget_meta(layout, widget_id) do
    Layout.put_meta(layout, :widget, %{id: widget_id})
  end

  defp monitor_alert_widgets(%Monitor{} = monitor) do
    case extract_target_widgets(monitor.target) do
      nil ->
        nil

      [] ->
        []

      widgets when is_list(widgets) ->
        widgets
        |> Enum.with_index()
        |> Enum.map(&build_alert_widget(monitor, &1))
        |> Enum.reject(&is_nil/1)
    end
  end

  defp extract_target_widgets(%{"widgets" => widgets}) when is_list(widgets), do: widgets
  defp extract_target_widgets(%{widgets: widgets}) when is_list(widgets), do: widgets
  defp extract_target_widgets(_), do: nil

  defp build_alert_widget(%Monitor{} = monitor, {widget, index}) when is_map(widget) do
    widget
    |> normalize_widget_map()
    |> adapt_alert_widget(monitor, index)
  end

  defp build_alert_widget(_monitor, _entry), do: nil

  defp normalize_widget_map(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      string_key = to_string(key)

      normalized_value =
        cond do
          is_map(value) ->
            normalize_widget_map(value)

          is_list(value) ->
            Enum.map(value, fn elem ->
              if is_map(elem), do: normalize_widget_map(elem), else: elem
            end)

          true ->
            value
        end

      Map.put(acc, string_key, normalized_value)
    end)
  end

  defp normalize_widget_map(other), do: other

  defp adapt_alert_widget(widget, monitor, index) when is_map(widget) do
    type =
      widget
      |> Map.get("type", "timeseries")
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> case do
        "" -> "timeseries"
        value -> value
      end

    normalized = Map.put(widget, "type", type)

    base_id =
      normalized
      |> Map.get("id")
      |> case do
        nil -> nil
        value -> value |> to_string() |> String.trim()
      end

    generated_id =
      base_id
      |> case do
        "" -> nil
        value -> value
      end || "#{monitor.id}-alert-widget-#{index}"

    layout = extract_widget_layout(normalized, index)

    cleaned_widget =
      normalized
      |> Map.drop(["layout", "dataset", :layout, :dataset])
      |> Map.put("id", generated_id)
      |> Map.put("title", widget_title(normalized, monitor))
      |> Map.merge(layout)

    dataset = normalized |> Map.get("dataset", %{}) |> normalize_widget_map()

    cleaned_widget
    |> apply_type_specific_defaults(type, normalized, dataset, monitor)
    |> ensure_default_booleans(type, normalized, dataset)
    |> sanitize_widget_values()
  end

  defp adapt_alert_widget(_widget, _monitor, _index), do: nil

  defp widget_title(widget, monitor) do
    widget
    |> Map.get("title")
    |> case do
      nil ->
        widget |> Map.get("label") || monitor.alert_metric_key || monitor.name || "Alert widget"

      title ->
        title
    end
  end

  defp extract_widget_layout(widget, index) do
    layout = widget["layout"] || %{}

    %{
      "w" => coerce_int(layout["w"] || layout["width"] || widget["w"] || widget["width"], 12),
      "h" => coerce_int(layout["h"] || layout["height"] || widget["h"] || widget["height"], 5),
      "x" => coerce_int(layout["x"] || layout["column"] || widget["x"], default_x(index)),
      "y" => coerce_int(layout["y"] || layout["row"] || widget["y"], default_y(index))
    }
  end

  defp default_x(index), do: rem(index, 2) * 6
  defp default_y(index), do: div(index, 2) * 6

  defp apply_type_specific_defaults(widget, "timeseries" = _type, original, dataset, monitor) do
    paths =
      []
      |> concat_paths(original["paths"])
      |> concat_paths(dataset["paths"])
      |> concat_paths(original["path"])
      |> concat_paths(dataset["path"])
      |> concat_paths(original["metric_path"])
      |> concat_paths(original["metric_paths"])
      |> concat_paths(dataset["metric_path"])
      |> concat_paths(dataset["metric_paths"])
      |> case do
        [] -> concat_paths([], monitor.alert_metric_path)
        other -> other
      end

    widget =
      widget
      |> Map.put("paths", paths)

    widget
    |> maybe_put(original, dataset, "chart_type", "line")
    |> maybe_put(original, dataset, "legend", false)
    |> maybe_put(original, dataset, "stacked", false)
    |> maybe_put(original, dataset, "normalized", false)
    |> maybe_put(original, dataset, "y_label", monitor.alert_metric_path)
  end

  defp apply_type_specific_defaults(widget, "kpi", original, dataset, _monitor) do
    widget
    |> maybe_put(original, dataset, "stat_type", "number")
    |> maybe_put(original, dataset, "comparison", false)
  end

  defp apply_type_specific_defaults(widget, "category", original, dataset, _monitor) do
    widget
    |> maybe_put(original, dataset, "path", nil)
    |> maybe_put(original, dataset, "limit", 5)
  end

  defp apply_type_specific_defaults(widget, _other, _original, _dataset, _monitor), do: widget

  defp ensure_default_booleans(widget, "timeseries", original, dataset) do
    widget
    |> ensure_boolean("legend", original, dataset, false)
    |> ensure_boolean("stacked", original, dataset, false)
    |> ensure_boolean("normalized", original, dataset, false)
  end

  defp ensure_default_booleans(widget, _type, _original, _dataset), do: widget

  defp ensure_boolean(widget, key, original, dataset, fallback) do
    value = coerce_bool(widget[key] || original[key] || dataset[key], fallback)
    Map.put(widget, key, value)
  end

  defp maybe_put(widget, original, dataset, key, default) do
    value =
      widget[key] || original[key] || dataset[key] || default

    case value do
      nil -> widget
      _ -> Map.put(widget, key, value)
    end
  end

  defp concat_paths(list, value) when is_list(list) do
    sanitized =
      value
      |> normalize_path_list()
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    list ++ sanitized
  end

  defp concat_paths(list, value) do
    concat_paths(list, normalize_path_list(value))
  end

  defp normalize_path_list(value) when is_list(value), do: value
  defp normalize_path_list(value) when is_binary(value), do: [value]
  defp normalize_path_list(value) when is_atom(value), do: [Atom.to_string(value)]
  defp normalize_path_list(value) when is_number(value), do: [to_string(value)]
  defp normalize_path_list(_), do: []

  defp sanitize_widget_values(%{} = widget) do
    widget
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      cond do
        key in ["w", "h", "x", "y"] ->
          Map.put(acc, key, coerce_int(value, acc_default(key)))

        key in ["legend", "stacked", "normalized", "comparison"] ->
          Map.put(acc, key, coerce_bool(value, false))

        key == "paths" ->
          Map.put(acc, key, ensure_list_of_strings(value))

        true ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp acc_default("w"), do: 12
  defp acc_default("h"), do: 5
  defp acc_default("x"), do: 0
  defp acc_default("y"), do: 0
  defp acc_default(_), do: nil

  defp ensure_list_of_strings(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp ensure_list_of_strings(value), do: ensure_list_of_strings(List.wrap(value))

  defp coerce_int(value, default) when is_integer(value), do: value
  defp coerce_int(value, default) when is_float(value), do: round(value)

  defp coerce_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> default
    end
  end

  defp coerce_int(true, default), do: if(default, do: default, else: 1)
  defp coerce_int(false, default), do: default
  defp coerce_int(nil, default), do: default
  defp coerce_int(_other, default), do: default

  defp coerce_bool(value, default) when is_boolean(value), do: value

  defp coerce_bool(value, default) when is_binary(value) do
    value = String.downcase(String.trim(value))

    cond do
      value in ["true", "1", "yes", "on"] -> true
      value in ["false", "0", "no", "off"] -> false
      true -> default
    end
  end

  defp coerce_bool(value, default) when is_integer(value), do: value != 0
  defp coerce_bool(_other, default), do: default

  defp build_default_alert_widgets(_monitor, ""), do: []

  defp build_default_alert_widgets(monitor, metric_path) do
    [
      %{
        "id" => "#{monitor.id}-alert-series",
        "type" => "timeseries",
        "title" => monitor.alert_metric_key || monitor.name || "Alert series",
        "chart_type" => "line",
        "legend" => false,
        "stacked" => false,
        "normalized" => false,
        "paths" => [metric_path],
        "y_label" => metric_path,
        "w" => 12,
        "h" => 5,
        "x" => 0,
        "y" => 0
      }
    ]
  end

  defp compute_report_time_range(%Monitor{} = monitor, timeframe_input, config) do
    settings = monitor.report_settings || %{}
    frequency = Map.get(settings, :frequency)
    now = timezone_now(config)

    cond do
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
