defmodule Trifle.Billing.UsageRecorder do
  @moduledoc """
  Counts ingested events per project and writes the totals to
  `project_billing_usage` in batches.

  The ingest path calls `record/2`, which only bumps an in-memory counter. Every
  `:billing_usage_flush_interval_ms` (default 10 seconds) the counters are drained
  and each total is added to its usage row, so ingest never pays a database write
  per request.

  Counters are kept per project **and per second of receipt**. The second is
  passed on when the count is written, so events accepted just before a
  subscription renews are added to the period they arrived in, not to the new
  one, however late they are flushed.

  ## Failures

  A write is one transaction (`Billing.record_project_event_usage!/3`).

    * It raised before reaching its commit: nothing was stored; the count is kept
      and retried on the next flush, with its original receipt time.
    * It raised while committing (the connection dropped at that moment): it is
      unknown whether the count was stored. It is dropped, because counting it
      twice could lock a paying project out, while losing it costs a few events.
    * It returned an error that a retry cannot fix (invalid row): dropped.
    * A count that has been retried for an hour is dropped.

  Every dropped count is logged.

  ## Limits of batching

    * A project can overshoot its hard limit by what arrives within one flush
      interval (per node), plus the ingest access cache TTL.
    * Counts held in memory are lost if the node is killed. A normal shutdown
      flushes first.

  Nothing is counted when billing is disabled (self-hosted).
  """

  use GenServer

  require Logger

  alias Trifle.Billing
  alias Trifle.Organizations.Project

  @table __MODULE__
  @default_flush_interval_ms 10_000
  @max_retry_age_seconds 3_600

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Adds `count` ingested events for the project, received now. Cheap and
  non-blocking.
  """
  def record(project, count \\ 1, now \\ nil)

  def record(%Project{id: id, organization_id: organization_id}, count, now)
      when is_binary(id) and is_integer(count) and count > 0 do
    if Billing.enabled?() do
      key = {id, organization_id, now || System.os_time(:second)}

      try do
        :ets.update_counter(@table, key, {2, count}, {key, 0})
      rescue
        # The table is missing only while the recorder restarts.
        ArgumentError -> :ok
      end
    end

    :ok
  end

  def record(_project, _count, _now), do: :ok

  @doc """
  Writes all pending counts now, in the calling process. Returns the number of
  counts that were settled (stored or dropped); retried ones are not included.
  """
  def flush do
    @table
    |> :ets.select([{{:"$1", :_}, [], [:"$1"]}])
    |> Enum.sort_by(fn {_id, _organization_id, second} -> second end)
    |> Enum.count(&flush_key/1)
  rescue
    ArgumentError -> 0
  end

  defp flush_key({project_id, organization_id, second} = key) do
    case :ets.take(@table, key) do
      [{^key, count}] when count > 0 ->
        project = %Project{id: project_id, organization_id: organization_id}
        write(project, key, count, DateTime.from_unix!(second))

      _ ->
        false
    end
  end

  defp write(project, key, count, received_at) do
    Process.delete(:usage_recording_reached_commit)

    result =
      try do
        Billing.record_project_event_usage!(project, count, received_at)
      rescue
        error -> {:raised, error, Process.get(:usage_recording_reached_commit) == true}
      end

    case result do
      {:raised, error, false} ->
        retry_or_drop(project, key, count, received_at, error)

      {:raised, error, true} ->
        dropped(project, count, "the commit failed and may or may not have been applied", error)
        true

      {:ok, %Trifle.Billing.ProjectUsage{} = usage} ->
        after_commit(project, usage)
        true

      {:error, :project_subscription_required} ->
        # No subscription (anymore): nothing to count against.
        true

      {:error, reason} ->
        dropped(project, count, "it cannot be stored", reason)
        true

      _other ->
        true
    end
  end

  # The count is already stored; nothing here may cause it to be retried.
  defp after_commit(project, usage) do
    # A project that just reached its limit must not keep its cached "allowed" answer.
    if usage.locked_at, do: Trifle.Cache.invalidate({:project_ingest_allowed, project.id})
    :ok
  rescue
    _ -> :ok
  end

  defp retry_or_drop(project, key, count, received_at, error) do
    age = DateTime.diff(DateTime.utc_now(), received_at, :second)

    if age > @max_retry_age_seconds do
      dropped(project, count, "it could not be stored for #{age} seconds", error)
      true
    else
      :ets.update_counter(@table, key, {2, count}, {key, 0})

      Logger.warning(
        "[UsageRecorder] will retry #{count} events for project #{project.id}: " <>
          describe(error)
      )

      false
    end
  end

  defp dropped(project, count, why, reason) do
    Logger.error(
      "[UsageRecorder] dropped #{count} events for project #{project.id} because #{why}: " <>
        describe(reason)
    )
  end

  defp describe(%{__exception__: true} = error), do: Exception.message(error)
  defp describe(other), do: inspect(other)

  ## Server

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])

    schedule_flush()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:flush, state) do
    flush()
    schedule_flush()
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, _state) do
    flush()
    :ok
  end

  # An interval of 0 disables the timer (tests flush by hand).
  defp schedule_flush do
    case Application.get_env(
           :trifle,
           :billing_usage_flush_interval_ms,
           @default_flush_interval_ms
         ) do
      interval when is_integer(interval) and interval > 0 ->
        Process.send_after(self(), :flush, interval)

      _ ->
        :ok
    end
  end
end
