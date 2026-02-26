defmodule Trifle.DatabasePools.VersionRegistry do
  @moduledoc """
  Tracks active pool versions per database and driver on each node.
  """

  use GenServer

  @table :trifle_database_pool_versions

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])
    end

    {:ok, %{}}
  end

  def get(pool_type, database_id) when is_atom(pool_type) and is_binary(database_id) do
    case :ets.lookup(@table, {pool_type, database_id}) do
      [{{^pool_type, ^database_id}, version}] -> {:ok, version}
      [] -> :error
    end
  rescue
    ArgumentError -> :error
  end

  def put(pool_type, database_id, version)
      when is_atom(pool_type) and is_binary(database_id) and is_integer(version) do
    true = :ets.insert(@table, {{pool_type, database_id}, version})
    :ok
  rescue
    ArgumentError -> :error
  end

  def delete(pool_type, database_id) when is_atom(pool_type) and is_binary(database_id) do
    :ets.delete(@table, {pool_type, database_id})
    :ok
  rescue
    ArgumentError -> :ok
  end
end
