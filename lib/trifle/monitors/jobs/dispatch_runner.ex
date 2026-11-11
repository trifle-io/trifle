defmodule Trifle.Monitors.Jobs.DispatchRunner do
  @moduledoc """
  Cron-driven worker that periodically scans all active monitors and enqueues
  evaluation jobs when their schedule or alert granularity demands it.
  """

  use Oban.Worker,
    queue: :monitors,
    max_attempts: 1,
    unique: [period: 60, fields: [:args, :queue]]

  require Logger

  import Ecto.Query

  alias Trifle.Monitors.Monitor
  alias Trifle.Monitors.Schedule
  alias Trifle.Monitors.Execution
  alias Trifle.Monitors.Jobs.EvaluateMonitor
  alias Trifle.Repo
  alias Trifle.Traces

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, scheduled_at: scheduled_at}) do
    Traces.trace("Dispatch due monitors", head: true)

    now =
      args
      |> Map.get("dispatched_at")
      |> parse_scheduled_at(scheduled_at)

    Traces.trace("Dispatch time: #{format_dt(now)}")
    Traces.trace("Load active and paused-alert monitors", head: true)
    monitors = Repo.all(monitors_query())
    Traces.trace("Eligible monitors: #{length(monitors)}")

    Traces.trace("Load recent monitor executions", head: true)

    report_ids = for %Monitor{type: :report, id: id} <- monitors, do: id
    alert_ids = for %Monitor{type: :alert, id: id} <- monitors, do: id

    reports_last_any = last_execution_map(report_ids, "report")
    reports_last_success = last_execution_map(report_ids, "report", ["ok"])
    alerts_last = last_execution_map(alert_ids, "alert")

    Logger.debug(fn ->
      "[DispatchRunner] monitors=" <>
        inspect(Enum.map(monitors, &{&1.id, &1.type, &1.status}), limit: :infinity)
    end)

    summary =
      monitors
      |> Enum.with_index(1)
      |> Enum.reduce(%{due: 0, enqueued: 0, skipped: 0, failed: 0}, fn
        {monitor, position}, summary ->
          Traces.trace("Monitor #{position} of #{length(monitors)}", head: true)
          Traces.tag("monitor:#{monitor.id}")
          Traces.trace("Monitor configuration", fn -> monitor end)
          Traces.trace("Type: #{monitor.type}; status: #{monitor.status}")

          last_attempt =
            case monitor.type do
              :report -> Map.get(reports_last_any, monitor.id)
              :alert -> Map.get(alerts_last, monitor.id)
              _ -> nil
            end

          last_success =
            case monitor.type do
              :report -> Map.get(reports_last_success, monitor.id)
              :alert -> last_attempt
              _ -> nil
            end

          Logger.debug(fn ->
            "[DispatchRunner] evaluate monitor=#{monitor.id} type=#{monitor.type} last_success=#{format_dt(last_success)} last_attempt=#{format_dt(last_attempt)} now=#{format_dt(now)}"
          end)

          schedule_reference =
            case monitor.type do
              :report -> last_success
              _ -> last_success || last_attempt
            end

          first_run? = monitor.type == :report and is_nil(last_attempt)

          due? =
            cond do
              first_run? -> true
              true -> Schedule.due?(monitor, now, schedule_reference)
            end

          Logger.debug(fn ->
            "[DispatchRunner] check monitor=#{monitor.id} type=#{monitor.type} due=#{due?} first_run=#{first_run?} last_success=#{format_dt(last_success)} last_attempt=#{format_dt(last_attempt)} now=#{format_dt(now)}"
          end)

          Traces.trace(
            "Schedule reference: #{format_dt(schedule_reference)}; first run: #{first_run?}"
          )

          Traces.trace("Due for evaluation: #{due?}")

          if due? do
            Logger.debug(fn ->
              "[DispatchRunner] enqueue #{monitor.type} monitor=#{monitor.id} at=#{DateTime.to_iso8601(now)}"
            end)

            Traces.trace("Enqueue monitor evaluation")

            case enqueue_monitor(monitor, now, last_success || last_attempt) do
              {:ok, job} ->
                Traces.tag("evaluation-job:#{job.id}")
                Traces.trace("Evaluation job enqueued")

                summary
                |> Map.update!(:due, &(&1 + 1))
                |> Map.update!(:enqueued, &(&1 + 1))

              {:error, _reason} ->
                Traces.trace("Evaluation job enqueue failed", state: :error)
                Traces.fail()

                summary
                |> Map.update!(:due, &(&1 + 1))
                |> Map.update!(:failed, &(&1 + 1))
            end
          else
            Map.update!(summary, :skipped, &(&1 + 1))
          end
      end)

    Traces.trace("Dispatch summary", head: true)

    Traces.trace(
      "Due: #{summary.due}; enqueued: #{summary.enqueued}; skipped: #{summary.skipped}; failed: #{summary.failed}"
    )

    :ok
  end

  defp parse_scheduled_at(nil, %DateTime{} = fallback), do: DateTime.truncate(fallback, :second)
  defp parse_scheduled_at(nil, nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp parse_scheduled_at(iso, _fallback) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> parse_scheduled_at(nil, nil)
    end
  end

  defp parse_scheduled_at(_other, fallback), do: parse_scheduled_at(nil, fallback)

  defp monitors_query do
    from(m in Monitor,
      where: m.status == :active or (m.status == :paused and m.type == :alert),
      order_by: [asc: m.inserted_at]
    )
  end

  @doc """
  Latest execution time per monitor for the given execution kind.

  This runs every minute, so it must not grow with execution history. Instead of
  aggregating the whole `monitor_executions` table, it does one index seek per
  eligible monitor (newest row first) on
  `monitor_executions_monitor_kind_triggered_index`. The `details->>'kind'`
  expression is written literally so it matches that index.
  """
  def last_execution_map(monitor_ids, kind, statuses \\ nil)

  def last_execution_map([], _kind, _statuses), do: %{}

  def last_execution_map(monitor_ids, kind, statuses)
      when is_list(monitor_ids) and is_binary(kind) do
    latest =
      from(e in Execution,
        where: e.monitor_id == parent_as(:monitor).id,
        where: fragment("(?->>'kind') = ?", e.details, ^kind),
        order_by: [desc: e.triggered_at],
        limit: 1,
        select: %{triggered_at: e.triggered_at}
      )

    latest =
      case statuses do
        list when is_list(list) and list != [] -> where(latest, [e], e.status in ^list)
        _ -> latest
      end

    from(m in Monitor,
      as: :monitor,
      where: m.id in ^monitor_ids,
      inner_lateral_join: e in subquery(latest),
      on: true,
      select: {m.id, e.triggered_at}
    )
    |> Repo.all()
    |> Map.new()
  end

  defp enqueue_monitor(%Monitor{id: monitor_id, type: type}, now, last_triggered) do
    scheduled_iso =
      now
      |> truncate_to_minute()
      |> DateTime.to_iso8601()

    args = %{
      "monitor_id" => monitor_id,
      "scheduled_for" => scheduled_iso
    }

    queue =
      case type do
        :report -> :reports
        :alert -> :alerts
        _ -> :monitors
      end

    changeset = EvaluateMonitor.new(args, queue: queue)

    Logger.debug(fn ->
      "[DispatchRunner] attempt enqueue monitor=#{monitor_id} queue=#{queue} scheduled_for=#{scheduled_iso} last_triggered=#{inspect(last_triggered)}"
    end)

    case Oban.insert(changeset) do
      {:ok, job} ->
        Logger.debug(fn ->
          "[DispatchRunner] job=#{job.id} state=#{job.state} scheduled_at=#{inspect(job.scheduled_at)}"
        end)

        {:ok, job}

      {:error, %Ecto.Changeset{} = cs} ->
        Logger.warning(
          "Failed to enqueue monitor #{monitor_id}: #{inspect(Ecto.Changeset.traverse_errors(cs, fn {msg, _} -> msg end))}"
        )

        {:error, cs}

      {:error, reason} ->
        Logger.warning("Failed to enqueue monitor #{monitor_id}: #{inspect(reason)}")

        {:error, reason}
    end
  end

  defp truncate_to_minute(%DateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}
  defp truncate_to_minute(%NaiveDateTime{} = dt), do: %{dt | second: 0, microsecond: {0, 0}}
  defp truncate_to_minute(other), do: other

  defp format_dt(nil), do: "nil"
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_dt(other), do: inspect(other)
end
