defmodule TrifleApp.Components.DashboardWidgets.Timeseries do
  @moduledoc false

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers
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

    path_sources =
      case raw_paths do
        [] -> fallback_paths
        list -> list
      end

    paths =
      path_sources
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    chart_type = String.downcase(to_string(item["chart_type"] || "line"))
    stacked = !!item["stacked"]
    normalized = !!item["normalized"]
    legend = !!item["legend"]
    y_label = to_string(item["y_label"] || "")

    timeline_callback = fn at, value ->
      utc_dt =
        cond do
          match?(%DateTime{}, at) ->
            DateTime.shift_zone!(at, "Etc/UTC")

          match?(%NaiveDateTime{}, at) ->
            DateTime.from_naive!(at, "Etc/UTC")

          true ->
            nil
        end

      ts =
        case utc_dt do
          %DateTime{} = dt -> DateTime.to_unix(dt, :millisecond)
          _ -> nil
        end

      val =
        case value do
          %Decimal{} = d -> Decimal.to_float(d)
          v when is_number(v) -> v * 1.0
          _ -> 0.0
        end

      [ts || 0, val]
    end

    path_inputs =
      item
      |> WidgetHelpers.path_inputs_for_form("timeseries")
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)

    selectors =
      item
      |> Map.get("series_color_selectors", %{})
      |> WidgetHelpers.normalize_series_color_selectors_map()

    path_specs =
      paths
      |> Enum.with_index()
      |> Enum.map(fn {path, index} ->
        path_input =
          path_inputs
          |> Enum.at(index)
          |> case do
            nil -> path
            "" -> path
            value -> value
          end

        %{path: path, path_input: path_input}
      end)

    per_path =
      Enum.reduce(path_specs, [], fn %{path: path, path_input: path_input}, acc ->
        timeline_map = format_timeline_map(series_struct, path, 1, timeline_callback)

        selector = WidgetHelpers.selector_for_path(selectors, path_input)

        timeline_map
        |> Enum.sort_by(fn {series_path, _data} -> to_string(series_path) end)
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {{series_path, data}, emitted_index}, inner_acc ->
          name = to_string(series_path)
          normalized_data = normalize_timeline_points(data)
          color = WidgetHelpers.resolve_series_color(selector, emitted_index)

          series_entry = %{name: name, data: normalized_data, color: color}

          case Enum.find_index(inner_acc, &(&1.name == name)) do
            nil ->
              inner_acc ++ [series_entry]

            idx ->
              List.update_at(inner_acc, idx, fn _ -> series_entry end)
          end
        end)
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
