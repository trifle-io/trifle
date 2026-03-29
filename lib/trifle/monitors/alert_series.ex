defmodule Trifle.Monitors.AlertSeries do
  @moduledoc false

  require Logger

  alias Trifle.Monitors.Monitor
  alias Trifle.Stats.Series

  alias TrifleApp.Components.DashboardWidgets.{
    Helpers,
    MetricSeries,
    MetricSeriesEvaluator
  }

  @default_color_selector "default.*"
  @source_widget_height 7

  def normalize_rows(rows, opts \\ []) do
    MetricSeries.normalize_series_rows(rows, opts)
  end

  def normalize_rows_params(params, prefix \\ "alert_series", opts \\ [])

  def normalize_rows_params(params, prefix, opts) when is_map(params) do
    MetricSeries.normalize_series_rows_params(
      %{
        "widget_series_kind" => fetch_param_value(params, "#{prefix}_kind"),
        "widget_series_path" => fetch_param_value(params, "#{prefix}_path"),
        "widget_series_expression" => fetch_param_value(params, "#{prefix}_expression"),
        "widget_series_label" => fetch_param_value(params, "#{prefix}_label"),
        "widget_series_visible" => fetch_param_value(params, "#{prefix}_visible"),
        "widget_series_color_selector" => fetch_param_value(params, "#{prefix}_color_selector")
      },
      opts
    )
  end

  def normalize_rows_params(_params, _prefix, opts),
    do: normalize_rows([], opts)

  def row_params_present?(params, prefix \\ "alert_series")

  def row_params_present?(params, prefix) when is_map(params) do
    Enum.any?(
      [
        "#{prefix}_kind",
        "#{prefix}_path",
        "#{prefix}_expression",
        "#{prefix}_label",
        "#{prefix}_visible",
        "#{prefix}_color_selector"
      ],
      fn key -> Map.has_key?(params, key) || Map.has_key?(params, "#{key}[]") end
    )
  end

  def row_params_present?(_params, _prefix), do: false

  def normalize_attrs(attrs, prefix \\ "alert_series")

  def normalize_attrs(attrs, prefix) when is_map(attrs) do
    cond do
      row_params_present?(attrs, prefix) ->
        rows = normalize_rows_params(attrs, prefix, ensure_default: false)

        attrs
        |> put_value(:alert_series, rows)
        |> put_value(:alert_metric_path, legacy_metric_path(rows))

      has_value_key?(attrs, :alert_series) ->
        rows = normalize_rows(fetch_value(attrs, :alert_series), ensure_default: false)

        attrs
        |> put_value(:alert_series, rows)
        |> put_value(:alert_metric_path, legacy_metric_path(rows))

      has_value_key?(attrs, :alert_metric_path) ->
        rows =
          normalize_rows(legacy_rows(fetch_value(attrs, :alert_metric_path)),
            ensure_default: false
          )

        attrs
        |> put_value(:alert_series, rows)
        |> put_value(:alert_metric_path, legacy_metric_path(rows))

      true ->
        attrs
    end
  end

  def normalize_attrs(attrs, _prefix), do: attrs

  def normalize_monitor(monitor, opts \\ [])

  def normalize_monitor(%Monitor{} = monitor, opts) do
    rows = normalize_rows(current_rows(monitor), opts)
    %{monitor | alert_series: rows, alert_metric_path: legacy_metric_path(rows)}
  end

  def normalize_monitor(%{} = monitor, opts) do
    rows = normalize_rows(current_rows(monitor), opts)

    monitor
    |> Map.put(:alert_series, rows)
    |> Map.put(:alert_metric_path, legacy_metric_path(rows))
  end

  def normalize_monitor(other, _opts), do: other

  def rows(monitor, opts \\ [])

  def rows(%Monitor{} = monitor, opts) do
    monitor
    |> normalize_monitor(opts)
    |> Map.get(:alert_series, [])
  end

  def rows(%{} = monitor, opts) do
    monitor
    |> normalize_monitor(opts)
    |> Map.get(:alert_series, [])
  end

  def rows(_monitor, _opts), do: []

  def final_row(%Monitor{} = monitor), do: monitor |> rows() |> final_row()
  def final_row(%{} = monitor), do: monitor |> rows() |> final_row()

  def final_row(rows) when is_list(rows),
    do: List.last(normalize_rows(rows, ensure_default: false))

  def final_row(_), do: nil

  def has_final_row?(monitor), do: not is_nil(final_row(monitor))

  def series_count(monitor) do
    monitor
    |> rows()
    |> length()
  end

  def final_row_display(monitor) do
    case final_row(monitor) do
      nil ->
        ""

      row ->
        if MetricSeries.path_row?(row) do
          MetricSeries.row_path(row)
        else
          MetricSeries.row_expression(row)
        end
    end
  end

  def final_row_label(monitor) do
    monitor
    |> final_row()
    |> case do
      nil -> ""
      row -> MetricSeries.row_label(row)
    end
  end

  def legacy_metric_path(monitor_or_rows) do
    row = final_row(monitor_or_rows)

    if is_map(row) and MetricSeries.path_row?(row) do
      MetricSeries.row_path(row)
    else
      ""
    end
  end

  def source_widget(%Monitor{} = monitor) do
    source_widget(%{
      id: monitor.id,
      alert_metric_key: monitor.alert_metric_key,
      alert_series: rows(monitor)
    })
  end

  def source_widget(%{} = monitor) do
    %{
      "id" => source_widget_id(monitor),
      "type" => "timeseries",
      "title" => "Source series",
      "chart_type" => "line",
      "legend" => true,
      "stacked" => false,
      "normalized" => false,
      "series" => rows(monitor),
      "y_label" => fetch_value(monitor, :alert_metric_key) || "",
      "w" => 12,
      "h" => @source_widget_height,
      "x" => 0,
      "y" => 0
    }
  end

  def source_widget(_), do: source_widget(%{})

  def source_widget_id(%Monitor{id: id}), do: source_widget_id(%{id: id})

  def source_widget_id(%{} = monitor) do
    monitor_id =
      fetch_value(monitor, :id)
      |> case do
        nil -> "monitor"
        value -> to_string(value)
      end

    "#{monitor_id}-alert-source"
  end

  def source_widget_id(_monitor), do: "monitor-alert-source"

  def source_widget_height, do: @source_widget_height

  def resolved_final_targets(%Series{} = stats, %Monitor{} = monitor) do
    widget = source_widget(monitor)

    case MetricSeriesEvaluator.resolve_timeline_rows(stats, widget) |> List.last() do
      %{entries: entries, row: row, index: row_index} when is_map(entries) ->
        entries
        |> Enum.sort_by(fn {binding_key, entry} ->
          {to_string(Map.get(entry, :name) || ""), binding_sort_key(binding_key)}
        end)
        |> Enum.with_index()
        |> Enum.map(fn {{binding_key, entry}, emitted_index} ->
          points =
            entry
            |> Map.get(:samples, %{})
            |> samples_to_points()
            |> Enum.reject(&is_nil(Map.get(&1, :value)))

          %{
            index: emitted_index,
            row_index: row_index,
            binding_key: binding_key,
            row: row,
            name: Map.get(entry, :name) || target_name(entry, emitted_index),
            source_path: Map.get(entry, :source_path),
            color:
              row
              |> MetricSeries.row_color_selector()
              |> Helpers.resolve_series_color(emitted_index),
            points: points,
            data:
              Enum.map(points, fn point ->
                [Map.get(point, :ts), Map.get(point, :value)]
              end)
          }
        end)
        |> Enum.reject(fn target -> target.points == [] end)

      _ ->
        []
    end
  end

  def resolved_final_targets(_stats, _monitor), do: []

  defp current_rows(%Monitor{} = monitor) do
    monitor.alert_series
    |> case do
      list when is_list(list) and list != [] -> list
      _ -> legacy_rows(monitor.alert_metric_path)
    end
  end

  defp current_rows(%{} = monitor) do
    fetch_value(monitor, :alert_series)
    |> case do
      list when is_list(list) and list != [] -> list
      _ -> legacy_rows(fetch_value(monitor, :alert_metric_path))
    end
  end

  defp current_rows(_), do: []

  defp legacy_rows(path) do
    case path |> to_string() |> String.trim() do
      "" ->
        []

      value ->
        [
          %{
            "kind" => "path",
            "path" => value,
            "expression" => "",
            "label" => "",
            "visible" => true,
            "color_selector" => @default_color_selector
          }
        ]
    end
  end

  defp fetch_value(map, key) when is_atom(key) and is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> fetch_value(map, Atom.to_string(key))
    end
  end

  defp fetch_value(map, key) when is_binary(key) and is_map(map) do
    fetch_param_value(map, key)
  end

  defp fetch_value(_map, _key), do: nil

  defp fetch_param_value(map, key) when is_binary(key) and is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, "#{key}[]")
    end
  end

  defp fetch_param_value(_map, _key), do: nil

  defp has_value_key?(attrs, key) when is_atom(key) and is_map(attrs) do
    Map.has_key?(attrs, key) || Map.has_key?(attrs, Atom.to_string(key))
  end

  defp has_value_key?(_attrs, _key), do: false

  defp put_value(attrs, key, value) when is_atom(key) and is_map(attrs) do
    target_key = preferred_key(attrs, key)

    attrs
    |> Map.delete(alternate_key(target_key))
    |> Map.put(target_key, value)
  end

  defp put_value(attrs, _key, _value), do: attrs

  defp preferred_key(attrs, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) and not Map.has_key?(attrs, string_key) -> key
      Map.has_key?(attrs, string_key) -> string_key
      has_string_keys?(attrs) -> string_key
      true -> key
    end
  end

  defp alternate_key(key) when is_atom(key), do: Atom.to_string(key)
  defp alternate_key(key) when is_binary(key), do: safe_to_existing_atom(key)
  defp alternate_key(_key), do: nil

  defp safe_to_existing_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp safe_to_existing_atom(value), do: value

  defp has_string_keys?(attrs) when is_map(attrs) do
    Enum.any?(Map.keys(attrs), &is_binary/1)
  end

  defp has_string_keys?(_attrs), do: false

  defp target_name(entry, emitted_index) do
    case Map.get(entry, :source_path) do
      value when is_binary(value) and value != "" -> value
      _ -> "Series #{emitted_index + 1}"
    end
  end

  defp samples_to_points(samples) when is_map(samples) do
    samples
    |> Enum.sort_by(fn {sample_key, _value} -> sample_sort_key(sample_key) end)
    |> Enum.map(fn {sample_key, value} ->
      datetime = normalize_datetime(sample_key)

      %{
        at: datetime,
        at_iso: datetime && DateTime.to_iso8601(datetime),
        ts: datetime && DateTime.to_unix(datetime, :millisecond),
        value: normalize_number(value)
      }
    end)
    |> Enum.filter(& &1.at_iso)
  end

  defp samples_to_points(_samples), do: []

  defp normalize_datetime(%DateTime{} = dt), do: DateTime.shift_zone!(dt, "Etc/UTC")

  defp normalize_datetime(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
  rescue
    exception ->
      Logger.warning(
        "AlertSeries.normalize_datetime/1 failed DateTime.from_naive! for #{inspect(naive)}: #{Exception.message(exception)}"
      )

      nil
  end

  defp normalize_datetime(_), do: nil

  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value
  defp normalize_number(%Decimal{} = value), do: Decimal.to_float(value)
  defp normalize_number(_), do: nil

  defp sample_sort_key(%DateTime{} = dt), do: {:datetime, DateTime.to_unix(dt, :microsecond)}
  defp sample_sort_key(%NaiveDateTime{} = dt), do: {:naive_datetime, NaiveDateTime.to_iso8601(dt)}
  defp sample_sort_key(value) when is_integer(value), do: {:integer, value}
  defp sample_sort_key(value) when is_float(value), do: {:float, value}
  defp sample_sort_key(value), do: {:string, to_string(value)}

  defp binding_sort_key({:captures, captures}), do: Enum.map(captures, &to_string/1)
  defp binding_sort_key(other), do: to_string(other)
end
