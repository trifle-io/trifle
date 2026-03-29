defmodule Trifle.Monitors.AlertEvaluator.Utils do
  @moduledoc false

  alias Trifle.Monitors.AlertEvaluator

  @spec build_series_aggregation(list(), keyword()) :: AlertEvaluator.result()
  def build_series_aggregation(results, opts \\ []) when is_list(results) do
    successful = Enum.filter(results, &successful_result?/1)
    failures = Enum.reject(results, &successful_result?/1)
    triggered = Enum.filter(successful, &Map.get(result_for(&1), :triggered?, false))

    base_result =
      case List.first(triggered) || List.first(successful) do
        entry ->
          case result_for(entry) do
            %AlertEvaluator.Result{} = result -> result
            _ -> %AlertEvaluator.Result{}
          end
      end

    summary = aggregation_summary(successful, triggered, base_result)

    meta =
      (base_result.meta || %{})
      |> Map.put(:series_count, length(results))
      |> Map.put(
        :series_results,
        Enum.map(successful, fn entry ->
          target = target_for(entry)
          result = result_for(entry)

          %{
            name: target_name(target),
            source_path: target_source_path(target),
            triggered: Map.get(result, :triggered?, false),
            summary: Map.get(result, :summary),
            meta: Map.get(result, :meta) || %{}
          }
        end)
      )
      |> Map.put(
        :series_errors,
        Enum.map(failures, fn entry ->
          target = target_for(entry)

          %{
            name: target_name(target),
            source_path: target_source_path(target),
            error: error_for(entry)
          }
        end)
      )

    %AlertEvaluator.Result{
      base_result
      | alert_id: Keyword.get(opts, :alert_id, base_result.alert_id),
        strategy: Keyword.get(opts, :strategy, base_result.strategy),
        triggered?: triggered != [],
        summary: summary,
        meta: meta
    }
  end

  defp aggregation_summary([], _triggered, %AlertEvaluator.Result{}) do
    "Alert evaluation failed for all resolved series."
  end

  defp aggregation_summary(successful, [], %AlertEvaluator.Result{} = base_result)
       when length(successful) <= 1 do
    base_result.summary || "No recent breaches detected."
  end

  defp aggregation_summary(successful, [], %AlertEvaluator.Result{}) do
    "No recent breaches detected across #{length(successful)} series."
  end

  defp aggregation_summary(_successful, [trigger], _base_result) do
    result = result_for(trigger)
    target = target_for(trigger)

    "#{target_name(target)}: #{Map.get(result, :summary) || "Triggered in the latest evaluation window."}"
  end

  defp aggregation_summary(_successful, triggered, _base_result) do
    names =
      triggered
      |> Enum.map(&target_for/1)
      |> Enum.map(&target_name/1)
      |> Enum.join(", ")

    "#{length(triggered)} series triggered: #{names}."
  end

  defp successful_result?(entry) do
    match?(%AlertEvaluator.Result{}, result_for(entry))
  end

  defp target_for(entry) when is_map(entry), do: Map.get(entry, :target) || %{}
  defp target_for(_entry), do: %{}

  defp result_for(entry) when is_map(entry), do: Map.get(entry, :result)
  defp result_for(_entry), do: nil

  defp error_for(entry) when is_map(entry) do
    Map.get(entry, :error) ||
      entry
      |> result_for()
      |> case do
        %{} = result -> Map.get(result, :error)
        _ -> nil
      end
  end

  defp error_for(_entry), do: nil

  defp target_name(target) when is_map(target),
    do: Map.get(target, :name) || Map.get(target, "name")

  defp target_name(_target), do: nil

  defp target_source_path(target) when is_map(target),
    do: Map.get(target, :source_path) || Map.get(target, "source_path")

  defp target_source_path(_target), do: nil
end
