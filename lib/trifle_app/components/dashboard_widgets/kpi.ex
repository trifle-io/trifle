defmodule TrifleApp.Components.DashboardWidgets.Kpi do
  @moduledoc false

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers
  alias TrifleApp.Components.DashboardWidgets.Timeseries, as: TimeseriesWidgets

  @spec datasets(Series.t() | nil, list()) :: {list(), list()}
  def datasets(nil, _grid_items), do: {[], []}

  def datasets(series_struct, grid_items) do
    grid_items
    |> Enum.filter(fn item ->
      String.downcase(to_string(item["type"] || "kpi")) == "kpi"
    end)
    |> Enum.reduce({[], []}, fn item, {value_acc, visual_acc} ->
      case dataset(series_struct, item) do
        nil ->
          {value_acc, visual_acc}

        {value_map, nil} ->
          {[value_map | value_acc], visual_acc}

        {value_map, visual_map} ->
          {[value_map | value_acc], [visual_map | visual_acc]}
      end
    end)
    |> then(fn {value_items, visual_items} ->
      {Enum.reverse(value_items), Enum.reverse(visual_items)}
    end)
  end

  @spec dataset(Series.t() | nil, map()) :: {map(), map() | nil} | nil
  def dataset(nil, _item), do: nil

  def dataset(series_struct, item) do
    id = to_string(item["id"])
    path = to_string(item["path"] || "")
    func = String.downcase(to_string(item["function"] || "mean"))
    size = to_string(item["size"] || "m")
    subtype = WidgetHelpers.normalize_kpi_subtype(item["subtype"], item)

    case subtype do
      "split" ->
        list =
          aggregate_for_function(series_struct, path, func, 2)
          |> List.wrap()

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
            %{id: id, type: "sparkline", data: build_timeline(series_struct, path)}
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
          if is_number(value) and is_number(target) and target != 0 do
            value / target
          else
            nil
          end

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
            %{id: id, type: "sparkline", data: build_timeline(series_struct, path)}
          end

        {value_map, visual_map}
    end
  end

  defp build_timeline(series_struct, path) do
    normalized_path = to_string(path || "")

    timeline_map =
      TimeseriesWidgets.format_timeline_map(series_struct, normalized_path, 1, fn at, value ->
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

    TimeseriesWidgets.extract_timeline_series(timeline_map, normalized_path)
  end

  defp aggregate_for_function(series_struct, path, func, slices) do
    case func do
      "sum" -> Series.aggregate_sum(series_struct, path, slices)
      "min" -> Series.aggregate_min(series_struct, path, slices)
      "max" -> Series.aggregate_max(series_struct, path, slices)
      _ -> Series.aggregate_mean(series_struct, path, slices)
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
end
