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
        monitor = Repo.preload(monitor, [:alerts, :dashboard])
        scheduled_for = parse_scheduled_for(job.args["scheduled_for"])
        log_monitor_start(monitor, scheduled_for)

        try do
          handle_monitor(monitor, scheduled_for)
        rescue
          exception ->
            stacktrace = __STACKTRACE__
            handle_monitor_exception(monitor, scheduled_for, exception, stacktrace)
        end

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
    report_settings = monitor.report_settings || %{}

    Logger.debug(fn ->
      "[EvaluateMonitor] deliver report monitor=#{monitor.id} freq=#{Map.get(report_settings, :frequency)} timeframe=#{Map.get(report_settings, :timeframe)} granularity=#{Map.get(report_settings, :granularity)} channels=#{length(monitor.delivery_channels || [])}"
    end)

    case TestDelivery.deliver_monitor(monitor) do
      {:ok, result} ->
        Logger.debug(fn ->
          "[EvaluateMonitor] report delivered monitor=#{monitor.id} keys=#{inspect(Map.keys(result || %{}))}"
        end)

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
        Logger.debug(fn ->
          "[EvaluateMonitor] report delivery failed monitor=#{monitor.id} reason=#{inspect(reason)}"
        end)

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
        Logger.debug(fn ->
          "[EvaluateMonitor] skip alert monitor=#{monitor.id} reason=missing_metric_path"
        end)

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
        Logger.debug(fn ->
          "[EvaluateMonitor] skip alert monitor=#{monitor.id} reason=no_alerts"
        end)

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
        Logger.debug(fn ->
          "[EvaluateMonitor] evaluate alert monitor=#{monitor.id} alerts=#{length(monitor.alerts || [])} timeframe=#{monitor.alert_timeframe} granularity=#{monitor.alert_granularity} notify_every=#{monitor.alert_notify_every}"
        end)

        evaluate_alerts(monitor, scheduled_for)
    end
  end

  defp handle_monitor(_monitor, _scheduled_for), do: :ok

  defp monitor_kind(%Monitor{type: type}) when type in [:report, :alert],
    do: Atom.to_string(type)

  defp monitor_kind(_monitor), do: "monitor"

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
      recoveries = recovered_alerts(evaluations)

      deliveries =
        deliver_triggered_alerts(monitor, triggered, timeframe) ++
          deliver_recovered_alerts(monitor, recoveries, timeframe)

      status = execution_status(triggered, deliveries, evaluations)

      Logger.debug(fn ->
        "[EvaluateMonitor] alert evaluated monitor=#{monitor.id} triggered=#{length(triggered)} recoveries=#{length(recoveries)} deliveries=#{format_delivery_stats(deliveries)} status=#{status}"
      end)

      log_execution(monitor, %{
        status: status,
        summary: build_alert_summary(triggered, recoveries, deliveries, evaluations, status),
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
        Logger.debug(fn ->
          "[EvaluateMonitor] alert evaluation unexpected export response monitor=#{monitor.id}"
        end)

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

  defp log_monitor_start(%Monitor{} = monitor, scheduled_for) do
    Logger.debug(fn ->
      "[EvaluateMonitor] start monitor=#{monitor.id} type=#{monitor.type} status=#{monitor.status} scheduled_for=#{format_dt(scheduled_for)}"
    end)
  end

  defp format_delivery_stats(deliveries) do
    counts =
      Enum.reduce(deliveries, %{success: 0, error: 0, suppressed: 0}, fn
        {:ok, _alert, _}, acc -> Map.update!(acc, :success, &(&1 + 1))
        {:error, _alert, _}, acc -> Map.update!(acc, :error, &(&1 + 1))
        {:suppressed, _alert, _}, acc -> Map.update!(acc, :suppressed, &(&1 + 1))
        _other, acc -> acc
      end)

    "success=#{counts.success} error=#{counts.error} suppressed=#{counts.suppressed}"
  end

  defp format_dt(nil), do: "nil"
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_dt(other), do: inspect(other)

  defp handle_monitor_exception(%Monitor{} = monitor, scheduled_for, exception, stacktrace) do
    Logger.error(fn ->
      [
        "[EvaluateMonitor] crash monitor=#{monitor.id} type=#{monitor.type} ",
        Exception.format(:error, exception, stacktrace)
      ]
      |> IO.iodata_to_binary()
    end)

    log_execution(monitor, %{
      status: "failed",
      summary: "Monitor evaluation crashed: #{Exception.message(exception)}",
      details: %{
        kind: monitor_kind(monitor),
        scheduled_for: scheduled_for,
        reason: "exception",
        error: Exception.message(exception),
        exception: inspect(exception),
        stacktrace: format_stacktrace(stacktrace)
      }
    })

    reraise(exception, stacktrace)
  end

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    stacktrace
    |> Enum.take(15)
    |> Enum.map(&Exception.format_stacktrace_entry/1)
  end

  defp format_stacktrace(_other), do: []

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

  defp recovered_alerts(evaluations) do
    Enum.filter(evaluations, fn
      %{alert: %Alert{status: status}, result: result, status: :ok}
      when status in [:alerted, :suppressed] ->
        not Map.get(result, :triggered?, false)

      _ ->
        false
    end)
  end

  defp deliver_triggered_alerts(_monitor, [], _timeframe), do: []

  defp deliver_triggered_alerts(monitor, triggered, timeframe) do
    deliver_alert_events(monitor, triggered, timeframe, :triggered)
  end

  defp deliver_recovered_alerts(_monitor, [], _timeframe), do: []

  defp deliver_recovered_alerts(monitor, recoveries, timeframe) do
    deliver_alert_events(monitor, recoveries, timeframe, :recovered)
  end

  defp deliver_alert_events(monitor, events, timeframe, trigger_type) do
    notify_every = normalize_notify_every(monitor.alert_notify_every)

    Enum.map(events, fn %{alert: %Alert{} = alert} ->
      cond do
        monitor.status == :paused ->
          {:suppressed, alert, %{reason: :monitor_paused, event: trigger_type}}

        trigger_type == :triggered and not deliver_on_frequency?(alert, notify_every) ->
          {:suppressed, alert,
           %{reason: :notify_every, notify_every: notify_every, event: trigger_type}}

        true ->
          case TestDelivery.deliver_alert(monitor, alert,
                 export_params: timeframe,
                 trigger_type: trigger_type
               ) do
            {:ok, payload} ->
              {:ok, alert, %{payload: prune_large_values(payload), event: trigger_type}}

            {:error, reason} ->
              Logger.warning(
                "Alert delivery failed for monitor #{monitor.id} alert #{alert.id}: #{inspect(reason)}"
              )

              {:error, alert, %{reason: format_reason(reason), event: trigger_type}}
          end
      end
    end)
  end

  defp execution_status(triggered, deliveries, evaluations) do
    triggered_ids =
      triggered
      |> Enum.map(fn
        %{alert: %Alert{id: id}} -> id
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    evaluation_failed? = Enum.any?(evaluations, &(&1.status != :ok))

    delivery_failed? =
      Enum.any?(deliveries, fn
        {:error, _, _} -> true
        _ -> false
      end)

    delivery_suppressed? =
      Enum.any?(deliveries, fn
        {:suppressed, %Alert{id: id}, meta} ->
          MapSet.member?(triggered_ids, id) and delivery_event_type(meta) == :triggered

        _ ->
          false
      end)

    delivery_succeeded? =
      Enum.any?(deliveries, fn
        {:ok, %Alert{id: id}, meta} ->
          MapSet.member?(triggered_ids, id) and delivery_event_type(meta) == :triggered

        _ ->
          false
      end)

    triggered_any? =
      Enum.any?(triggered, fn
        %{result: %{triggered?: true}} -> true
        _ -> false
      end)

    cond do
      evaluation_failed? or delivery_failed? -> "failed"
      delivery_succeeded? -> "alerted"
      delivery_suppressed? and triggered_any? -> "suppressed"
      triggered_any? -> "alerted"
      true -> "passed"
    end
  end

  defp build_alert_summary(triggered, recoveries, deliveries, evaluations, status) do
    trigger_summary = build_trigger_summary(triggered, deliveries, evaluations, status)
    recovery_summary = build_recovery_summary(recoveries, deliveries)

    cond do
      recovery_summary && trigger_summary ->
        trigger_summary <> " " <> recovery_summary

      recovery_summary ->
        recovery_summary

      true ->
        trigger_summary
    end
  end

  defp build_trigger_summary([], _deliveries, _evaluations, "passed"),
    do: "No alerts triggered."

  defp build_trigger_summary(triggered, _deliveries, _evaluations, "alerted") do
    triggered_ids = triggered |> Enum.map(&alert_label/1) |> Enum.join(", ")
    "Delivered alerts for #{triggered_ids}."
  end

  defp build_trigger_summary(triggered, deliveries, _evaluations, "suppressed") do
    triggered_ids = triggered |> Enum.map(&alert_label/1) |> Enum.join(", ")

    reasons =
      deliveries
      |> Enum.reduce([], fn
        {:suppressed, _, meta}, acc ->
          case suppression_reason_description(meta) do
            nil -> acc
            description -> [description | acc]
          end

        _, acc ->
          acc
      end)
      |> Enum.uniq()
      |> Enum.join("; ")

    cond do
      triggered_ids == "" ->
        if reasons == "" do
          "Alert notifications suppressed."
        else
          "Alert notifications suppressed (#{reasons})."
        end

      reasons == "" ->
        "Alerts triggered for #{triggered_ids}, notifications suppressed."

      true ->
        "Alerts triggered for #{triggered_ids}, notifications suppressed (#{reasons})."
    end
  end

  defp build_trigger_summary(triggered, deliveries, evaluations, "failed") do
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

  defp build_trigger_summary(_triggered, _deliveries, _evaluations, _status),
    do: "Alert processing completed."

  defp build_recovery_summary([], _deliveries), do: nil

  defp build_recovery_summary(_recoveries, deliveries) do
    {successes, failures, suppressed} =
      Enum.reduce(deliveries, {[], [], []}, fn
        {:ok, %Alert{} = alert, meta}, {succ, fail, sup} ->
          if delivery_event_type(meta) == :recovered do
            {[alert_label(alert) | succ], fail, sup}
          else
            {succ, fail, sup}
          end

        {:error, %Alert{} = alert, meta}, {succ, fail, sup} ->
          if delivery_event_type(meta) == :recovered do
            {succ, [alert_label(alert) | fail], sup}
          else
            {succ, fail, sup}
          end

        {:suppressed, %Alert{} = alert, meta}, {succ, fail, sup} ->
          if delivery_event_type(meta) == :recovered do
            {succ, fail, [alert_label(alert) | sup]}
          else
            {succ, fail, sup}
          end

        _, acc ->
          acc
      end)

    []
    |> maybe_add_recovery_part(successes, "Recovery notifications sent for ")
    |> maybe_add_recovery_part(failures, "Recovery notifications failed for ")
    |> maybe_add_recovery_part(suppressed, "Recovery notifications suppressed for ")
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " ")
    end
  end

  defp maybe_add_recovery_part(parts, [], _prefix), do: parts

  defp maybe_add_recovery_part(parts, labels, prefix) do
    formatted =
      labels
      |> Enum.reverse()
      |> Enum.join(", ")

    parts ++ ["#{prefix}#{formatted}."]
  end

  defp alert_label(%{alert: %Alert{id: id}}), do: "alert #{id}"
  defp alert_label(%Alert{id: id}), do: "alert #{id}"
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

  defp delivery_event_type(meta) when is_map(meta), do: Map.get(meta, :event, :triggered)
  defp delivery_event_type(_), do: :triggered

  defp notification_label(meta) do
    case delivery_event_type(meta) do
      :recovered -> "Recovery notification"
      :previewed -> "Preview notification"
      _ -> "Alert notification"
    end
  end

  defp format_deliveries(deliveries) do
    Enum.map(deliveries, fn
      {:ok, %Alert{id: id}, meta} ->
        %{
          alert_id: id,
          status: "success",
          event: delivery_event_type(meta) |> Atom.to_string()
        }
        |> maybe_put_payload(meta)

      {:error, %Alert{id: id}, meta} ->
        %{
          alert_id: id,
          status: "error",
          event: delivery_event_type(meta) |> Atom.to_string(),
          reason: Map.get(meta, :reason)
        }

      {:suppressed, %Alert{id: id}, meta} ->
        %{
          alert_id: id,
          status: "suppressed",
          event: delivery_event_type(meta) |> Atom.to_string(),
          reason: suppression_reason_label(meta)
        }
    end)
  end

  defp maybe_put_payload(map, meta) do
    case Map.get(meta, :payload) do
      nil -> map
      payload -> Map.put(map, :payload, payload)
    end
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

  defp normalize_notify_every(value) when is_integer(value) and value >= 1 do
    value
    |> min(100)
  end

  defp normalize_notify_every(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        1

      trimmed ->
        case Integer.parse(trimmed) do
          {int, ""} -> normalize_notify_every(int)
          _ -> 1
        end
    end
  end

  defp normalize_notify_every(_), do: 1

  defp deliver_on_frequency?(%Alert{} = alert, notify_every) when notify_every <= 1 do
    _ = alert
    true
  end

  defp deliver_on_frequency?(%Alert{} = alert, notify_every) do
    count = next_trigger_count(alert, true)
    rem(max(count - 1, 0), notify_every) == 0
  end

  defp next_trigger_count(%Alert{} = alert, true) do
    (alert.continuous_trigger_count || 0) + 1
  end

  defp next_trigger_count(_alert, false), do: 0

  defp suppression_summary(%{reason: :monitor_paused} = meta) do
    "#{notification_label(meta)} suppressed because the monitor is paused."
  end

  defp suppression_summary(%{reason: :notify_every, notify_every: notify_every} = meta)
       when is_integer(notify_every) do
    "#{notification_label(meta)} throttled (notify every #{notify_every} trigger(s))."
  end

  defp suppression_summary(%{reason: reason} = meta) when is_atom(reason) do
    formatted = reason |> Atom.to_string() |> String.replace("_", " ")
    "#{notification_label(meta)} suppressed (#{formatted})."
  end

  defp suppression_summary(meta), do: "#{notification_label(meta)} suppressed."

  defp suppression_reason_description(%{reason: :monitor_paused}), do: "monitor is paused"

  defp suppression_reason_description(%{reason: :notify_every, notify_every: notify_every})
       when is_integer(notify_every) do
    "notify every #{notify_every} trigger(s)"
  end

  defp suppression_reason_description(%{reason: reason}) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp suppression_reason_description(_), do: nil

  defp suppression_reason_label(%{reason: :monitor_paused}), do: "monitor_paused"

  defp suppression_reason_label(%{reason: :notify_every, notify_every: notify_every})
       when is_integer(notify_every) do
    "notify_every_#{notify_every}"
  end

  defp suppression_reason_label(%{reason: reason}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp suppression_reason_label(_), do: "suppressed"

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

    delivery_info =
      Enum.reduce(deliveries, %{}, fn
        {:ok, %Alert{id: id}, _}, acc ->
          Map.put(acc, id, :success)

        {:error, %Alert{id: id}, meta}, acc ->
          Map.put(acc, id, {:error, Map.get(meta, :reason)})

        {:suppressed, %Alert{id: id}, meta}, acc ->
          Map.put(acc, id, {:suppressed, meta})
      end)

    Enum.each(evaluations, fn %{
                                alert: %Alert{id: id} = alert,
                                result: result,
                                status: eval_status
                              } ->
      base_alert = Map.get(alerts_by_id, id, alert)
      triggered? = Map.get(result, :triggered?, false)
      delivery_entry = Map.get(delivery_info, id)

      new_status =
        cond do
          eval_status != :ok -> :failed
          match?({:error, _}, delivery_entry) -> :failed
          triggered? and match?({:suppressed, _}, delivery_entry) -> :suppressed
          triggered? -> :alerted
          true -> :passed
        end

      new_count =
        case eval_status do
          :ok ->
            next_trigger_count(base_alert, triggered?)

          _ ->
            0
        end

      summary =
        alert_summary_from_evaluation(
          result,
          new_status,
          eval_status,
          delivery_entry
        )

      maybe_update_alert_state(
        base_alert,
        new_status,
        summary,
        evaluated_at,
        continuous_trigger_count: new_count
      )
    end)
  end

  defp mark_all_alerts_failed(%Monitor{} = monitor, summary, evaluated_at) do
    monitor.alerts
    |> List.wrap()
    |> Enum.each(
      &maybe_update_alert_state(&1, :failed, summary, evaluated_at, continuous_trigger_count: 0)
    )
  end

  defp maybe_update_alert_state(%Alert{} = alert, status, summary, evaluated_at, opts \\ [])
       when status in [:passed, :alerted, :suppressed, :failed] do
    normalized_summary = normalize_summary(summary)
    current_summary = normalize_summary(alert.last_summary)
    current_count = alert.continuous_trigger_count
    new_count = Keyword.get(opts, :continuous_trigger_count)

    changes =
      %{}
      |> maybe_put_change(:status, status, alert.status)
      |> maybe_put_change(:last_summary, normalized_summary, current_summary)
      |> maybe_put_evaluated_at(evaluated_at, alert.last_evaluated_at)
      |> maybe_put_trigger_count(new_count, current_count)

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

  defp maybe_update_alert_state(_, _, _, _, _), do: :ok

  defp alert_summary_from_evaluation(result, _new_status, eval_status, _delivery_info)
       when eval_status != :ok do
    reason = Map.get(result, :error, "evaluation_error")
    "Alert evaluation failed: #{format_reason(reason)}"
  end

  defp alert_summary_from_evaluation(_result, _new_status, _eval_status, {:error, reason}) do
    "Alert delivery failed: #{format_reason(reason)}"
  end

  defp alert_summary_from_evaluation(_result, :suppressed, _eval_status, {:suppressed, meta}) do
    suppression_summary(meta)
  end

  defp alert_summary_from_evaluation(
         %AlertEvaluator.Result{} = result,
         _new_status,
         _eval_status,
         _delivery_info
       ) do
    summarize_alert_result(result)
  end

  defp alert_summary_from_evaluation(_result, _new_status, _eval_status, _delivery_info), do: nil

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

  defp maybe_put_trigger_count(map, nil, _current), do: map

  defp maybe_put_trigger_count(map, value, current) do
    maybe_put_change(map, :continuous_trigger_count, value, current)
  end

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
