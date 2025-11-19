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

  @impl Oban.Worker
  def perform(%Oban.Job{args: args, scheduled_at: scheduled_at}) do
    now =
      args
      |> Map.get("dispatched_at")
      |> parse_scheduled_at(scheduled_at)

    reports_last_any = last_execution_map("report")
    reports_last_success = last_execution_map("report", ["ok"])
    alerts_last = last_execution_map("alert")

    monitors = Repo.all(monitors_query())

    Logger.debug(fn ->
      "[DispatchRunner] monitors=" <>
        inspect(Enum.map(monitors, &{&1.id, &1.type, &1.status}), limit: :infinity)
    end)

    Enum.each(monitors, fn monitor ->
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

      if due? do
        Logger.debug(fn ->
          "[DispatchRunner] enqueue #{monitor.type} monitor=#{monitor.id} at=#{DateTime.to_iso8601(now)}"
        end)

        enqueue_monitor(monitor, now, last_success || last_attempt)
      else
        :ok
      end
    end)

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

  defp stream_monitors(callback) when is_function(callback, 1) do
    monitors_query()
    |> Repo.all()
    |> Enum.each(callback)
  end

  defp monitors_query do
    from(m in Monitor,
      where: m.status == :active or (m.status == :paused and m.type == :alert),
      order_by: [asc: m.inserted_at]
    )
  end

  defp last_execution_map(kind, statuses \\ nil) when is_binary(kind) do
    base_query =
      from(e in Execution,
        where: fragment("?->>? = ?", e.details, "kind", ^kind)
      )

    query =
      case statuses do
        list when is_list(list) and list != [] -> where(base_query, [e], e.status in ^list)
        _ -> base_query
      end

    query
    |> group_by([e], e.monitor_id)
    |> select([e], {e.monitor_id, max(e.triggered_at)})
    |> Repo.all()
    |> Map.new()
  end

  defp enqueue_monitor(%Monitor{id: monitor_id, type: type} = monitor, now, last_triggered) do
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

        :ok

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
