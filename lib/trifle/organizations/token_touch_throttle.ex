defmodule Trifle.Organizations.TokenTouchThrottle do
  @moduledoc """
  Rate-limits `last_used_at` audit writes for organization API tokens.

  Every authenticated API request touches its token; at ingest volume that
  becomes a Postgres UPDATE per request. This throttle allows at most one
  touch per token per interval. Entries live in a public ETS table so the
  request hot path never goes through the GenServer — the process only owns
  the table and evicts expired entries.

  A race between concurrent requests on the same token can allow an extra
  write; that is harmless for an audit-only field.
  """

  use GenServer

  @table :organization_api_token_touch_throttle
  @eviction_interval_ms 300_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Returns true at most once per interval for the given token hash,
  recording the touch. Subsequent calls within the interval return false.
  """
  def allow?(token_hash, interval_ms \\ interval_ms()) when is_binary(token_hash) do
    now = System.system_time(:millisecond)

    case :ets.lookup(@table, token_hash) do
      [{^token_hash, throttled_until}] when throttled_until > now ->
        false

      _ ->
        :ets.insert(@table, {token_hash, now + interval_ms})
        true
    end
  end

  def interval_ms do
    Application.get_env(:trifle, :organization_api_token_touch_interval_ms, 60_000)
  end

  @impl true
  def init(state) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [
            :set,
            :public,
            :named_table,
            read_concurrency: true,
            write_concurrency: true
          ])

        existing ->
          existing
      end

    Process.send_after(self(), :evict, @eviction_interval_ms)

    {:ok, Map.put(state, :table, table)}
  end

  @impl true
  def handle_info(:evict, %{table: table} = state) do
    now = System.system_time(:millisecond)

    _deleted =
      :ets.select_delete(table, [
        {{:"$1", :"$2"}, [{:"=<", :"$2", now}], [true]}
      ])

    Process.send_after(self(), :evict, @eviction_interval_ms)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
