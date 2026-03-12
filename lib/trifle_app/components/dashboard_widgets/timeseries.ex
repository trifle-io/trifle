defmodule TrifleApp.Components.DashboardWidgets.Timeseries do
  @moduledoc false

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator
  require Logger

  @spec datasets(Series.t() | nil, list()) :: list()
  def datasets(nil, _grid_items), do: []

  def datasets(series_struct, grid_items) do
    items =
      grid_items
      |> Enum.filter(fn item ->
        String.downcase(to_string(item["type"] || "")) == "timeseries"
      end)
      |> Enum.map(&dataset(series_struct, &1))
      |> Enum.reject(&is_nil/1)

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

  @spec dataset(Series.t() | nil, map()) :: map() | nil
  def dataset(nil, _item), do: nil

  def dataset(series_struct, item) do
    id = to_string(item["id"])
    chart_type = String.downcase(to_string(item["chart_type"] || "line"))
    stacked = !!item["stacked"]
    normalized = !!item["normalized"]
    legend = !!item["legend"]
    y_label = to_string(item["y_label"] || "")

    per_path =
      series_struct
      |> MetricSeriesEvaluator.resolve_timeline_rows(item)
      |> MetricSeriesEvaluator.timeline_series()
      |> Enum.reduce([], fn series_entry, acc ->
        case Enum.find_index(acc, &(&1.name == series_entry.name)) do
          nil -> acc ++ [series_entry]
          idx -> List.update_at(acc, idx, fn _ -> series_entry end)
        end
      end)

    series =
      if normalized and length(per_path) > 0 do
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
  end

  @spec format_timeline_map(Series.t(), String.t(), pos_integer(), function()) :: map()
  def format_timeline_map(series_struct, path, slices, callback) do
    result = Series.format_timeline(series_struct, path, slices, callback)

    cond do
      is_map(result) -> result
      is_list(result) -> %{path => result}
      true -> %{}
    end
  end

  @spec extract_timeline_series(map(), String.t()) :: list()
  def extract_timeline_series(timeline_map, path) do
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

  @spec normalize_timeline_points(list() | nil) :: list()
  def normalize_timeline_points(nil), do: []
  def normalize_timeline_points(list) when is_list(list), do: list
  def normalize_timeline_points(other), do: List.wrap(other)
end
