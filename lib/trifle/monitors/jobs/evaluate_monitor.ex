defmodule Trifle.Monitors.Jobs.EvaluateMonitor do
  @moduledoc """
  Runs the per-monitor evaluation pipeline: delivers scheduled reports or
  evaluates alert monitors and dispatches alert notifications when triggered.
  """

  use Oban.Worker,
    queue: :monitors,
    max_attempts: 1,
    priority: 1,
    unique: [period: 60, fields: [:args, :queue]]

  require Logger

  import Ecto.Changeset, only: [change: 2]

  alias Trifle.Monitors
  alias Trifle.Monitors.{Alert, Monitor}
  alias Trifle.Monitors.AlertEvaluator
  alias Trifle.Monitors.TestDelivery
  alias Trifle.Repo
  alias Trifle.Exports.Series, as: SeriesExport
  alias TrifleApp.Exports.MonitorLayout

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"monitor_id" => monitor_id}} = job) do
    case Repo.get(Monitor, monitor_id) do
      %Monitor{} = monitor ->
        monitor = Repo.preload(monitor, :alerts)
        scheduled_for = parse_scheduled_for(job.args["scheduled_for"])
        handle_monitor(monitor, scheduled_for)

      nil ->
        Logger.info("Monitor #{monitor_id} missing, skipping evaluation.")
        :discard
    end
  end

  defp parse_scheduled_for(nil), do: truncate_to_minute(DateTime.utc_now())

  defp parse_scheduled_for(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> truncate_to_minute(dt)
      _ -> parse_scheduled_for(nil)
    end
  end

  defp parse_scheduled_for(_other), do: parse_scheduled_for(nil)

  defp handle_monitor(%Monitor{type: :report} = monitor, scheduled_for) do
    case TestDelivery.deliver_monitor(monitor) do
      {:ok, result} ->
        log_execution(monitor, %{
          status: "ok",
          summary: "Report delivered successfully.",
          details: %{
            kind: "report",
            scheduled_for: scheduled_for,
            frequency: monitor.report_settings && monitor.report_settings.frequency,
            result: prune_large_values(result)
          }
        })

        :ok

      {:error, reason} ->
        log_execution(monitor, %{
          status: "error",
          summary: "Report delivery failed: #{format_reason(reason)}",
          details: %{
            kind: "report",
            scheduled_for: scheduled_for,
            frequency: monitor.report_settings && monitor.report_settings.frequency,
            error: format_reason(reason)
          }
        })

        {:error, reason}
    end
  end

  defp handle_monitor(%Monitor{type: :alert} = monitor, scheduled_for) do
    cond do
      not has_alert_metric?(monitor) ->
        log_execution(monitor, %{
          status: "skipped",
          summary: "Skipped alert evaluation – metric path not configured.",
          details: %{
            kind: "alert",
            scheduled_for: scheduled_for,
            reason: "missing_metric_path"
          }
        })

        :ok

      Enum.empty?(monitor.alerts || []) ->
        log_execution(monitor, %{
          status: "skipped",
          summary: "Skipped alert evaluation – no alerts configured.",
          details: %{
            kind: "alert",
            scheduled_for: scheduled_for,
            reason: "no_alerts"
          }
        })

        :ok

      true ->
        evaluate_alerts(monitor, scheduled_for)
    end
  end

  defp handle_monitor(_monitor, _scheduled_for), do: :ok

  defp has_alert_metric?(%Monitor{} = monitor) do
    monitor.alert_metric_path
    |> to_string()
    |> String.trim()
    |> Kernel.!=("")
  end

  defp evaluate_alerts(%Monitor{} = monitor, scheduled_for) do
    with {:ok, %{export: export, timeframe: timeframe}} <- MonitorLayout.series_export(monitor),
         true <- SeriesExport.has_data?(export),
         stats when not is_nil(stats) <- fetch_stats_struct(export),
         evaluations <- evaluate_each_alert(monitor, stats),
         {triggered, _non_triggered} <- Enum.split_with(evaluations, & &1.result.triggered?) do
      deliveries = deliver_triggered_alerts(monitor, triggered, timeframe)
      status = execution_status(triggered, deliveries, evaluations)

      log_execution(monitor, %{
        status: status,
        summary: build_alert_summary(triggered, deliveries, evaluations, status),
        details: %{
          kind: "alert",
          scheduled_for: scheduled_for,
          timeframe: prune_timeframe(timeframe),
          evaluations: map_evaluations(evaluations),
          deliveries: format_deliveries(deliveries)
        }
      })

      update_alert_statuses(monitor, evaluations, deliveries, scheduled_for)
      maybe_update_trigger_status(monitor, triggered)
    else
      false ->
        log_execution(monitor, %{
          status: "failed",
          summary: "Alert evaluation skipped – no series data available.",
          details: %{
            kind: "alert",
            scheduled_for: scheduled_for,
            reason: "no_data"
          }
        })

        mark_all_alerts_failed(
          monitor,
          "Alert evaluation skipped – no series data available.",
          scheduled_for
        )

        maybe_update_trigger_status(monitor, [])

      {:error, reason} ->
        log_execution(monitor, %{
          status: "failed",
          summary: "Alert evaluation failed: #{format_reason(reason)}",
          details: %{
            kind: "alert",
            scheduled_for: scheduled_for,
            error: format_reason(reason)
          }
        })

        mark_all_alerts_failed(
          monitor,
          "Alert evaluation failed: #{format_reason(reason)}",
          scheduled_for
        )

        {:error, reason}

      _ ->
        log_execution(monitor, %{
          status: "failed",
          summary: "Alert evaluation failed due to unexpected response.",
          details: %{
            kind: "alert",
            scheduled_for: scheduled_for,
            error: "unexpected_response"
          }
        })

        mark_all_alerts_failed(
          monitor,
          "Alert evaluation failed due to unexpected response.",
          scheduled_for
        )

        {:error, :unexpected_response}
    end
  end

  defp fetch_stats_struct(%SeriesExport.Result{} = export) do
    export.raw
    |> Map.get(:series)
  end

  defp fetch_stats_struct(_), do: nil

  defp evaluate_each_alert(%Monitor{} = monitor, stats) do
    metric_path =
      monitor.alert_metric_path
      |> to_string()
      |> String.trim()

    monitor.alerts
    |> Enum.map(fn %Alert{} = alert ->
      case AlertEvaluator.evaluate(alert, stats, metric_path) do
        {:ok, result} ->
          %{alert: alert, result: result, status: :ok}

        {:error, reason} ->
          Logger.warning(
            "Alert evaluation failed for monitor #{monitor.id} alert #{alert.id}: #{inspect(reason)}"
          )

          %{alert: alert, result: %{triggered?: false, error: reason}, status: :error}
      end
    end)
  end

  defp deliver_triggered_alerts(_monitor, [], _timeframe), do: []

  defp deliver_triggered_alerts(monitor, triggered, timeframe) do
    Enum.map(triggered, fn %{alert: alert} ->
      case TestDelivery.deliver_alert(monitor, alert, export_params: timeframe) do
        {:ok, payload} ->
          {:ok, alert, prune_large_values(payload)}

        {:error, reason} ->
          Logger.warning(
            "Alert delivery failed for monitor #{monitor.id} alert #{alert.id}: #{inspect(reason)}"
          )

          {:error, alert, format_reason(reason)}
      end
    end)
  end

  defp execution_status(triggered, deliveries, evaluations) do
    evaluation_failed? = Enum.any?(evaluations, &(&1.status != :ok))

    delivery_failed? =
      Enum.any?(deliveries, fn
        {:error, _, _} -> true
        _ -> false
      end)

    cond do
      evaluation_failed? or delivery_failed? -> "failed"
      Enum.any?(triggered) -> "alerted"
      true -> "passed"
    end
  end

  defp build_alert_summary([], _deliveries, _evaluations, "passed"),
    do: "No alerts triggered."

  defp build_alert_summary(triggered, _deliveries, _evaluations, "alerted") do
    triggered_ids = triggered |> Enum.map(&alert_label/1) |> Enum.join(", ")
    "Delivered alerts for #{triggered_ids}."
  end

  defp build_alert_summary(triggered, deliveries, evaluations, "failed") do
    triggered_ids = triggered |> Enum.map(&alert_label/1) |> Enum.join(", ")

    delivery_failed? =
      Enum.any?(deliveries, fn
        {:error, _, _} -> true
        _ -> false
      end)

    evaluation_failed? = Enum.any?(evaluations, &(&1.status != :ok))

    cond do
      delivery_failed? and triggered_ids != "" ->
        "Alerts triggered for #{triggered_ids}, but some deliveries failed."

      triggered_ids != "" ->
        "Alerts triggered for #{triggered_ids}, but evaluation failed."

      evaluation_failed? ->
        "Alert evaluation failed."

      true ->
        "Alert processing failed."
    end
  end

  defp build_alert_summary(_triggered, _deliveries, _evaluations, _status),
    do: "Alert processing completed."

  defp alert_label(%{alert: %Alert{id: id}}), do: "alert #{id}"
  defp alert_label(_), do: "unknown alert"

  defp map_evaluations(evaluations) do
    Enum.map(evaluations, fn %{alert: %Alert{id: id}, result: result, status: status} ->
      %{
        alert_id: id,
        status: status |> to_string(),
        triggered: Map.get(result, :triggered?, false),
        summary: Map.get(result, :summary),
        meta: Map.get(result, :meta),
        window: Map.get(result, :window)
      }
    end)
  end

  defp format_deliveries(deliveries) do
    Enum.map(deliveries, fn
      {:ok, %Alert{id: id}, payload} ->
        %{alert_id: id, status: "success", payload: payload}

      {:error, %Alert{id: id}, reason} ->
        %{alert_id: id, status: "error", reason: reason}
    end)
  end

  defp prune_large_values(value) when is_map(value) do
    value
    |> Enum.map(fn {key, val} -> {key, prune_large_values(val)} end)
    |> Enum.into(%{})
  end

  defp prune_large_values(value) when is_list(value) do
    Enum.map(value, &prune_large_values/1)
  end

  defp prune_large_values(value), do: value

  defp prune_timeframe(timeframe) when is_map(timeframe) do
    timeframe
    |> Enum.filter(fn {key, _} -> key in [:from, :to, :granularity, :timeframe, :display] end)
    |> Enum.into(%{})
  end

  defp prune_timeframe(_), do: %{}

  defp format_reason(%{message: message}) when is_binary(message), do: message

  defp format_reason(%Ecto.Changeset{} = changeset),
    do: inspect(Ecto.Changeset.traverse_errors(changeset, & &1))

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp log_execution(%Monitor{} = monitor, attrs) do
    attrs =
      attrs
      |> Map.put_new(:status, "passed")
      |> Map.update(:details, %{}, fn details ->
        details
        |> Map.put_new(:monitor_id, monitor.id)
        |> normalize_datetime_fields()
      end)

    case Monitors.create_execution(monitor, attrs) do
      {:ok, _execution} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to persist monitor execution: #{inspect(reason)}")
    end
  end

  defp maybe_update_trigger_status(%Monitor{type: :alert} = monitor, triggered) do
    new_status =
      case Enum.any?(triggered, fn
             %{result: %{triggered?: true}} -> true
             _ -> false
           end) do
        true -> :alerting
        false -> :idle
      end

    if new_status != monitor.trigger_status do
      monitor
      |> change(trigger_status: new_status)
      |> Repo.update()

      :ok
    else
      :ok
    end
  end

  defp maybe_update_trigger_status(_monitor, _triggered), do: :ok

  defp truncate_to_minute(%DateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}
  defp truncate_to_minute(%NaiveDateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}
  defp truncate_to_minute(other), do: other

  defp update_alert_statuses(%Monitor{} = monitor, evaluations, deliveries, evaluated_at) do
    alerts_by_id =
      monitor.alerts
      |> List.wrap()
      |> Enum.reduce(%{}, fn %Alert{id: id} = alert, acc -> Map.put(acc, id, alert) end)

    {delivery_status, delivery_errors} =
      Enum.reduce(deliveries, {%{}, %{}}, fn
        {:ok, %Alert{id: id}, _}, {status_map, error_map} ->
          {Map.put(status_map, id, :success), error_map}

        {:error, %Alert{id: id}, reason}, {status_map, error_map} ->
          {Map.put(status_map, id, :error), Map.put(error_map, id, reason)}
      end)

    Enum.each(evaluations, fn %{
                                alert: %Alert{id: id} = alert,
                                result: result,
                                status: eval_status
                              } ->
      base_alert = Map.get(alerts_by_id, id, alert)

      new_status =
        cond do
          eval_status != :ok -> :failed
          Map.get(delivery_status, id) == :error -> :failed
          Map.get(result, :triggered?, false) -> :alerted
          true -> :passed
        end

      summary =
        alert_summary_from_evaluation(
          result,
          new_status,
          eval_status,
          Map.get(delivery_status, id),
          Map.get(delivery_errors, id)
        )

      maybe_update_alert_state(base_alert, new_status, summary, evaluated_at)
    end)
  end

  defp mark_all_alerts_failed(%Monitor{} = monitor, summary, evaluated_at) do
    monitor.alerts
    |> List.wrap()
    |> Enum.each(&maybe_update_alert_state(&1, :failed, summary, evaluated_at))
  end

  defp maybe_update_alert_state(%Alert{} = alert, status, summary, evaluated_at)
       when status in [:passed, :alerted, :failed] do
    normalized_summary = normalize_summary(summary)
    current_summary = normalize_summary(alert.last_summary)

    changes =
      %{}
      |> maybe_put_change(:status, status, alert.status)
      |> maybe_put_change(:last_summary, normalized_summary, current_summary)
      |> maybe_put_evaluated_at(evaluated_at, alert.last_evaluated_at)

    case map_size(changes) do
      0 ->
        :ok

      _ ->
        case alert |> change(changes) |> Repo.update() do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.warning("Failed to update alert #{alert.id} status: #{inspect(reason)}")
            :error
        end
    end
  end

  defp maybe_update_alert_state(_, _, _, _), do: :ok

  defp alert_summary_from_evaluation(
         result,
         new_status,
         eval_status,
         delivery_status,
         delivery_error
       )
       when eval_status != :ok do
    reason = Map.get(result, :error, "evaluation_error")
    "Alert evaluation failed: #{format_reason(reason)}"
  end

  defp alert_summary_from_evaluation(_result, _new_status, _eval_status, :error, delivery_error) do
    case delivery_error do
      nil -> "Alert delivery failed."
      reason -> "Alert delivery failed: #{format_reason(reason)}"
    end
  end

  defp alert_summary_from_evaluation(
         %AlertEvaluator.Result{} = result,
         _new_status,
         _eval_status,
         _delivery_status,
         _delivery_error
       ) do
    summarize_alert_result(result)
  end

  defp alert_summary_from_evaluation(
         _result,
         _new_status,
         _eval_status,
         _delivery_status,
         _delivery_error
       ),
       do: nil

  defp summarize_alert_result(%AlertEvaluator.Result{summary: summary})
       when is_binary(summary) do
    summary
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp summarize_alert_result(%AlertEvaluator.Result{triggered?: true}) do
    "Triggered in the latest evaluation window."
  end

  defp summarize_alert_result(%AlertEvaluator.Result{triggered?: false}) do
    "No recent breaches detected."
  end

  defp summarize_alert_result(_), do: nil

  defp maybe_put_change(map, _field, value, value), do: map
  defp maybe_put_change(map, field, value, _current), do: Map.put(map, field, value)

  defp maybe_put_evaluated_at(map, nil, _current), do: map

  defp maybe_put_evaluated_at(map, value, current) do
    if current == value do
      map
    else
      Map.put(map, :last_evaluated_at, value)
    end
  end

  defp normalize_summary(summary) when is_binary(summary) do
    summary
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_summary(_), do: nil

  defp normalize_datetime_fields(details) when is_map(details) do
    details
    |> Enum.map(fn
      {key, %DateTime{} = dt} -> {key, DateTime.to_iso8601(dt)}
      other -> other
    end)
    |> Enum.into(%{})
  end

  defp normalize_datetime_fields(other), do: other
end
