defmodule TrifleApp.Components.DashboardWidgets.Kpi do
  @moduledoc false

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers
  alias TrifleApp.Components.DashboardWidgets.MetricSeries
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator

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
    func = String.downcase(to_string(item["function"] || "mean"))
    size = to_string(item["size"] || "m")
    subtype = WidgetHelpers.normalize_kpi_subtype(item["subtype"], item)
    slices = if subtype == "split", do: 2, else: 1

    scalar_rows = MetricSeriesEvaluator.resolve_kpi_scalar_rows(series_struct, item, slices, func)
    timeline_rows = MetricSeriesEvaluator.resolve_timeline_rows(series_struct, item)

    scalar_entry = MetricSeriesEvaluator.primary_kpi_entry(scalar_rows)
    timeline_entry = MetricSeriesEvaluator.primary_kpi_entry(timeline_rows)

    if is_nil(scalar_entry) do
      nil
    else
      visible_row =
        scalar_rows
        |> MetricSeriesEvaluator.visible_rows()
        |> List.first()
        |> case do
          nil -> nil
          resolved -> resolved.row
        end

      visual_color =
        visible_row
        |> case do
          nil -> WidgetHelpers.resolve_series_color(WidgetHelpers.default_series_color_selector(), 0)
          row -> WidgetHelpers.resolve_series_color(MetricSeries.row_color_selector(row), 0)
        end

      timeline_data = timeline_samples_to_points(timeline_entry)

      case subtype do
        "split" ->
          split_values = scalar_samples_to_values(scalar_entry)
          len = length(split_values)
          prev = if len >= 2, do: Enum.at(split_values, len - 2), else: nil
          curr = if len >= 1, do: Enum.at(split_values, len - 1), else: nil
          show_diff = !!item["diff"]
          has_visual = !!item["timeseries"] and timeline_data != []

          value_map =
            %{
              id: id,
              subtype: "split",
              size: size,
              current: curr,
              previous: prev,
              show_diff: show_diff,
              has_visual: has_visual,
              visual_type: if(has_visual, do: "sparkline", else: nil)
            }
            |> Map.put(:path, scalar_entry.source_path)

          visual_map =
            if has_visual do
              %{
                id: id,
                type: "sparkline",
                data: timeline_data,
                color: visual_color
              }
            end

          {value_map, visual_map}

        "goal" ->
          value =
            scalar_entry
            |> scalar_samples_to_values()
            |> List.last()

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
            |> Map.put(:path, scalar_entry.source_path)

          visual_map =
            if has_visual do
              %{
                id: id,
                type: "progress",
                current: value || 0.0,
                target: target,
                ratio: ratio,
                invert: invert_goal,
                color: visual_color
              }
            end

          {value_map, visual_map}

        _ ->
          value =
            scalar_entry
            |> scalar_samples_to_values()
            |> List.last()

          has_visual = !!item["timeseries"] and timeline_data != []

          value_map =
            %{
              id: id,
              subtype: "number",
              size: size,
              value: value,
              has_visual: has_visual,
              visual_type: if(has_visual, do: "sparkline", else: nil)
            }
            |> Map.put(:path, scalar_entry.source_path)

          visual_map =
            if has_visual do
              %{
                id: id,
                type: "sparkline",
                data: timeline_data,
                color: visual_color
              }
            end

          {value_map, visual_map}
      end
    end
  end

  defp scalar_samples_to_values(%{samples: samples}) when is_map(samples) do
    samples
    |> Enum.sort_by(fn {sample_key, _value} -> sample_key end)
    |> Enum.map(fn {_sample_key, value} -> to_number(value) end)
  end

  defp scalar_samples_to_values(_), do: []

  defp timeline_samples_to_points(%{samples: samples}) when is_map(samples) do
    samples
    |> Enum.sort_by(fn {at, _value} ->
      case at do
        %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
        %NaiveDateTime{} = dt -> NaiveDateTime.to_iso8601(dt)
        other -> other
      end
    end)
    |> Enum.map(fn {at, value} ->
      timestamp =
        case at do
          %DateTime{} = dt -> DateTime.to_unix(dt, :millisecond)
          %NaiveDateTime{} = dt -> dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond)
          _ -> 0
        end

      [timestamp, to_number(value) || 0.0]
    end)
  end

  defp timeline_samples_to_points(_), do: []

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
