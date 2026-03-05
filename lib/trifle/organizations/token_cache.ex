defmodule Trifle.Organizations.TokenCache do
  @moduledoc false

  use GenServer

  @table :organization_api_token_cache
  @topic "organization_api_tokens:invalidate"
  @eviction_interval_ms Application.compile_env(
                          :trifle,
                          :organization_api_token_cache_eviction_interval_ms,
                          60_000
                        )

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(token_hash) when is_binary(token_hash) do
    GenServer.call(__MODULE__, {:get, token_hash})
  end

  def put(token_hash, payload, ttl_ms)
      when is_binary(token_hash) and is_integer(ttl_ms) and ttl_ms > 0 do
    GenServer.call(__MODULE__, {:put, token_hash, payload, ttl_ms})
    :ok
  end

  def invalidate(token_hash) when is_binary(token_hash) do
    GenServer.cast(__MODULE__, {:invalidate, token_hash})
    :ok
  end

  @impl true
  def init(state) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:set, :private, :named_table, read_concurrency: true])

        existing ->
          existing
      end

    Phoenix.PubSub.subscribe(Trifle.PubSub, @topic)

    Process.send_after(self(), :evict, @eviction_interval_ms)

    {:ok, Map.put(state, :table, table)}
  end

  @impl true
  def handle_call({:get, token_hash}, _from, %{table: table} = state)
      when is_binary(token_hash) do
    now = System.system_time(:millisecond)

    result =
      case :ets.lookup(table, token_hash) do
        [{^token_hash, payload, expires_at}] when expires_at > now ->
          {:ok, payload}

        [{^token_hash, _payload, _expires_at}] ->
          :ets.delete(table, token_hash)
          :error

        _ ->
          :error
      end

    {:reply, result, state}
  end

  def handle_call({:put, token_hash, payload, ttl_ms}, _from, %{table: table} = state)
      when is_binary(token_hash) and is_integer(ttl_ms) and ttl_ms > 0 do
    expires_at = System.system_time(:millisecond) + ttl_ms
    :ets.insert(table, {token_hash, payload, expires_at})
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:invalidate, token_hash}, %{table: table} = state)
      when is_binary(token_hash) do
    :ets.delete(table, token_hash)
    Phoenix.PubSub.broadcast_from(Trifle.PubSub, self(), @topic, {:invalidate, token_hash})
    {:noreply, state}
  end

  @impl true
  def handle_info(:evict, %{table: table} = state) do
    now = System.system_time(:millisecond)

    _deleted =
      :ets.select_delete(table, [
        {{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", now}], [true]}
      ])

    Process.send_after(self(), :evict, @eviction_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info({:invalidate, token_hash}, %{table: table} = state)
      when is_binary(token_hash) do
    :ets.delete(table, token_hash)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
