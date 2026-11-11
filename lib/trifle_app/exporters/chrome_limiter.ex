defmodule TrifleApp.Exporters.ChromeLimiter do
  @moduledoc """
  Caps how many headless Chrome instances run at once on this node.

  Each export launches its own browser (several hundred MB). Without a cap a burst
  of export requests, or a batch of scheduled reports, can exhaust memory. Callers
  queue in arrival order and give up after `:wait_timeout_ms`.

  A slot is tied to the calling process: if the caller dies mid-export the slot is
  released by the monitor, so a crash can never leak capacity.

  Configuration (`config :trifle, TrifleApp.Exporters.ChromeLimiter, ...`):

    * `:max_concurrency` - simultaneous exports (default 2)
    * `:wait_timeout_ms` - how long a caller waits for a slot (default 120_000)
  """

  use GenServer

  @default_max_concurrency 2
  @default_wait_timeout_ms 120_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Runs `fun` while holding an export slot. Returns `fun`'s result, or
  `{:error, :export_busy}` when no slot became free in time.
  """
  def run(fun, opts \\ []) when is_function(fun, 0) do
    server = Keyword.get(opts, :server, __MODULE__)

    timeout =
      Keyword.get(opts, :wait_timeout_ms, config(:wait_timeout_ms, @default_wait_timeout_ms))

    case acquire(server, timeout) do
      {:ok, ref} ->
        try do
          fun.()
        after
          GenServer.cast(server, {:release, ref})
        end

      {:error, :export_busy} = busy ->
        busy

      # The limiter is not running (e.g. a script or test that did not start the
      # application tree): run unthrottled rather than fail the export.
      :not_running ->
        fun.()
    end
  end

  defp acquire(server, timeout) do
    ref = make_ref()

    try do
      GenServer.call(server, {:acquire, ref}, timeout)
    catch
      :exit, {:timeout, _} ->
        GenServer.cast(server, {:release, ref})
        {:error, :export_busy}

      :exit, {:noproc, _} ->
        :not_running
    end
  end

  @impl true
  def init(opts) do
    max = Keyword.get(opts, :max_concurrency, config(:max_concurrency, @default_max_concurrency))

    {:ok, %{max: max(max, 1), running: %{}, queue: :queue.new()}}
  end

  @impl true
  def handle_call({:acquire, ref}, {pid, _tag} = from, state) do
    if map_size(state.running) < state.max do
      {:reply, {:ok, ref}, grant(state, ref, pid)}
    else
      {:noreply, %{state | queue: :queue.in({ref, pid, from}, state.queue)}}
    end
  end

  @impl true
  def handle_cast({:release, ref}, state) do
    {:noreply, state |> release(ref) |> drain()}
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    ref =
      Enum.find_value(state.running, fn {ref, {_pid, mon}} -> if mon == monitor, do: ref end)

    state = if ref, do: release(state, ref), else: state
    {:noreply, drain(state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp grant(state, ref, pid) do
    monitor = Process.monitor(pid)
    %{state | running: Map.put(state.running, ref, {pid, monitor})}
  end

  # Releasing a ref that is still queued (its caller timed out) drops it from the queue.
  defp release(state, ref) do
    case Map.pop(state.running, ref) do
      {{_pid, monitor}, running} ->
        Process.demonitor(monitor, [:flush])
        %{state | running: running}

      {nil, _running} ->
        %{
          state
          | queue: :queue.filter(fn {queued, _pid, _from} -> queued != ref end, state.queue)
        }
    end
  end

  defp drain(state) do
    if map_size(state.running) < state.max do
      case :queue.out(state.queue) do
        {{:value, {ref, pid, from}}, queue} ->
          state = %{state | queue: queue}

          if Process.alive?(pid) do
            GenServer.reply(from, {:ok, ref})
            state |> grant(ref, pid) |> drain()
          else
            drain(state)
          end

        {:empty, _queue} ->
          state
      end
    else
      state
    end
  end

  defp config(key, default) do
    :trifle
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
