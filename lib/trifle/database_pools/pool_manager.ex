defmodule Trifle.DatabasePools.PoolManager do
  @moduledoc """
  Centralized pool management for database connections.

  Provides utilities for managing connection pools across different
  database types and cleaning up resources when databases are removed.
  """

  @doc """
  Stop all pools for a given database across all database types.

  This should be called when a database record is deleted to properly
  clean up all associated connection pools.
  """
  def stop_all_pools_for_database(database_id) do
    results = [
      Trifle.DatabasePools.PostgresPoolSupervisor.stop_postgres_pool(database_id),
      Trifle.DatabasePools.MongoPoolSupervisor.stop_mongo_pool(database_id),
      Trifle.DatabasePools.RedisPoolSupervisor.stop_redis_pool(database_id),
      Trifle.DatabasePools.SqlitePoolSupervisor.stop_sqlite_pool(database_id),
      Trifle.DatabasePools.MySQLPoolSupervisor.stop_mysql_pool(database_id)
    ]

    # Return :ok if all succeeded, or list of any errors
    errors = Enum.reject(results, &(&1 == :ok))
    if Enum.empty?(errors), do: :ok, else: {:partial_errors, errors}
  end

  @doc """
  Get information about all active pools for a database.

  Returns a map with database types as keys and pool info as values.
  """
  def get_database_pool_info(database_id) do
    %{
      postgres: Trifle.DatabasePools.PostgresPoolSupervisor.get_postgres_connection(database_id),
      mongo: Trifle.DatabasePools.MongoPoolSupervisor.get_mongo_connection(database_id),
      redis: Trifle.DatabasePools.RedisPoolSupervisor.get_redis_connection(database_id),
      sqlite: Trifle.DatabasePools.SqlitePoolSupervisor.get_sqlite_connection(database_id),
      mysql: Trifle.DatabasePools.MySQLPoolSupervisor.get_mysql_connection(database_id)
    }
  end

  @doc """
  Get overview of all active pools across all supervisors.

  Useful for monitoring and debugging connection pool usage.
  """
  def list_all_active_pools do
    %{
      postgres: Trifle.DatabasePools.PostgresPoolSupervisor.list_active_pools(),
      mongo: Trifle.DatabasePools.MongoPoolSupervisor.list_active_pools(),
      redis: Trifle.DatabasePools.RedisPoolSupervisor.list_active_pools(),
      sqlite: Trifle.DatabasePools.SqlitePoolSupervisor.list_active_pools(),
      mysql: Trifle.DatabasePools.MySQLPoolSupervisor.list_active_pools()
    }
  end

  @doc """
  Get count of active pools by database type.

  Returns a summary of how many pools are running for each database type.
  """
  def pool_counts do
    all_pools = list_all_active_pools()

    %{
      postgres: length(all_pools.postgres),
      mongo: length(all_pools.mongo),
      redis: length(all_pools.redis),
      sqlite: length(all_pools.sqlite),
      mysql: length(all_pools.mysql),
      total: all_pools |> Map.values() |> List.flatten() |> length()
    }
  end
end
