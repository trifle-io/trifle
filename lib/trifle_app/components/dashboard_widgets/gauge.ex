defmodule TrifleApp.Components.DashboardWidgets.Gauge do
  @moduledoc "Weighted timeframe and latest populated-bucket comparisons."
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator

  defdelegate summarize(samples), to: Trifle.Stats.MeasurementSummary

  def prefix_count_path(widget, prefix) do
    path = widget["gauge_count_path"] || ""

    if prefix not in [nil, ""] and String.starts_with?(path, "$.") do
      Map.put(widget, "gauge_count_path", prefix <> "." <> String.replace_prefix(path, "$.", ""))
    else
      widget
    end
  end

  def dataset(nil, _), do: nil

  def dataset(stats, widget) do
    resolved = MetricSeriesEvaluator.resolve_timeline_rows(stats, widget)
    selected = MetricSeriesEvaluator.primary_kpi_binding(resolved)

    if selected do
      {binding_key, entry} = selected

      counts =
        if widget["gauge_count_path"] not in [nil, ""] do
          count_widget = %{
            "series" => [
              %{"kind" => "path", "path" => widget["gauge_count_path"], "visible" => true}
            ]
          }

          count_entry =
            stats
            |> MetricSeriesEvaluator.resolve_timeline_rows(count_widget)
            |> MetricSeriesEvaluator.primary_kpi_entry(binding_key)

          if count_entry, do: count_entry.samples, else: %{}
        end

      summary =
        entry.samples
        |> Enum.map(fn {at, sum} ->
          {at, sum, if(is_nil(counts), do: 1, else: Map.get(counts, at))}
        end)
        |> summarize()

      %{
        id: to_string(widget["id"]),
        presentation: "gauge",
        series: [],
        gauge:
          Map.merge(summary, %{unit: widget["unit"] || "", maximum: number(widget["gauge_max"])})
      }
    end
  end

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp number(_), do: nil
end
