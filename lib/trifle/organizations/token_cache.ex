defmodule Trifle.Organizations.TokenCache do
  @moduledoc false

  use GenServer

  @table :organization_api_token_cache
  @topic "organization_api_tokens:invalidate"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(token_hash) when is_binary(token_hash) do
    ensure_table()

    now = System.system_time(:millisecond)

    case :ets.lookup(@table, token_hash) do
      [{^token_hash, payload, expires_at}] when expires_at > now ->
        {:ok, payload}

      [{^token_hash, _payload, _expires_at}] ->
        :ets.delete(@table, token_hash)
        :error

      _ ->
        :error
    end
  end

  def put(token_hash, payload, ttl_ms) when is_binary(token_hash) and is_integer(ttl_ms) and ttl_ms > 0 do
    ensure_table()
    expires_at = System.system_time(:millisecond) + ttl_ms
    :ets.insert(@table, {token_hash, payload, expires_at})
    :ok
  end

  def invalidate(token_hash) when is_binary(token_hash) do
    ensure_table()
    :ets.delete(@table, token_hash)
    Phoenix.PubSub.broadcast(Trifle.PubSub, @topic, {:invalidate, token_hash})
    :ok
  end

  @impl true
  def init(state) do
    ensure_table()
    Phoenix.PubSub.subscribe(Trifle.PubSub, @topic)
    {:ok, state}
  end

  @impl true
  def handle_info({:invalidate, token_hash}, state) when is_binary(token_hash) do
    ensure_table()
    :ets.delete(@table, token_hash)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      _table ->
        @table
    end
  end
end
