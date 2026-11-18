defmodule Trifle.Monitors.Jobs.PruneExecutions do
  @moduledoc """
  Deletes monitor execution history older than
  `config :trifle, :monitor_execution_retention_days`
  (`MONITOR_EXECUTION_RETENTION_DAYS`, default 30; 0 keeps everything).

  Two rows per monitor and kind are kept whatever their age, because the
  dispatcher schedules from them (`DispatchRunner.last_execution_map/3`):

    * the most recent execution, and
    * the most recent successful one.

  Without that, a report that runs less often than the retention period (a
  quarterly report against 30 days) would look like it had never run and be
  sent again.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 3_600, fields: [:worker]]

  require Logger

  alias Trifle.Repo

  @batch_size 5_000
  # Upper bound on one run, so a first run over a large backlog cannot hold the
  # queue for hours; the next day continues.
  @max_batches 400

  # A row may go when a newer row of the same monitor and kind exists that makes
  # it redundant: any newer row for a failed one, a newer successful row for a
  # successful one.
  @delete_sql """
  DELETE FROM monitor_executions
  WHERE id IN (
    SELECT e.id
    FROM monitor_executions e
    WHERE e.triggered_at < $1
      AND EXISTS (
        SELECT 1
        FROM monitor_executions n
        WHERE n.monitor_id = e.monitor_id
          AND (n.details->>'kind') IS NOT DISTINCT FROM (e.details->>'kind')
          AND n.triggered_at > e.triggered_at
          AND (e.status <> 'ok' OR n.status = 'ok')
      )
    LIMIT $2
  )
  """

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case retention_days() do
      days when days > 0 ->
        deleted = prune(DateTime.add(DateTime.utc_now(), -days * 86_400, :second))
        Logger.info("[PruneExecutions] deleted #{deleted} executions older than #{days} days")
        :ok

      _ ->
        :ok
    end
  end

  @doc "Deletes prunable executions triggered before `cutoff`. Returns how many."
  def prune(%DateTime{} = cutoff, batch_size \\ @batch_size) do
    Enum.reduce_while(1..@max_batches, 0, fn _batch, total ->
      %{num_rows: deleted} = Repo.query!(@delete_sql, [cutoff, batch_size], timeout: 60_000)

      if deleted < batch_size,
        do: {:halt, total + deleted},
        else: {:cont, total + deleted}
    end)
  end

  def retention_days do
    case Application.get_env(:trifle, :monitor_execution_retention_days, 30) do
      days when is_integer(days) and days >= 0 -> days
      _ -> 30
    end
  end
end
