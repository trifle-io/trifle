defmodule Trifle.DatabasePools.MongoProjectClusterPoolSupervisor do
  @moduledoc """
  Dynamic supervisor for MongoDB connections to project clusters.

  Each cluster gets its own connection pool with independent supervision.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new MongoDB connection pool for a project cluster configuration.
  Returns the connection name to use for queries.
  """
  def start_mongo_pool(%{id: cluster_id} = cluster) do
    connection_name = mongo_connection_name(cluster_id)

    case Process.whereis(connection_name) do
      nil ->
        child_spec = mongo_pool_spec(cluster, connection_name)

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, _pid} -> {:ok, connection_name}
          {:error, {:already_started, _pid}} -> {:ok, connection_name}
          error -> error
        end

      _pid ->
        {:ok, connection_name}
    end
  end

  @doc """
  Stop a MongoDB pool for a project cluster.
  """
  def stop_mongo_pool(cluster_id) do
    connection_name = mongo_connection_name(cluster_id)

    case Process.whereis(connection_name) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  defp mongo_connection_name(cluster_id) do
    "trifle_mongo_project_cluster_pool_#{cluster_id}"
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp mongo_pool_spec(cluster, connection_name) do
    url = build_mongo_url(cluster)

    cluster_config = cluster.config || %{}

    pool_size =
      case cluster_config["pool_size"] do
        nil -> 5
        val when is_integer(val) -> val
        val when is_binary(val) and val != "" -> String.to_integer(val)
        _ -> 5
      end

    pool_timeout =
      case cluster_config["pool_timeout"] do
        nil -> 5000
        val when is_integer(val) -> val
        val when is_binary(val) and val != "" -> String.to_integer(val)
        _ -> 5000
      end

    timeout =
      case cluster_config["timeout"] do
        nil -> 5000
        val when is_integer(val) -> val
        val when is_binary(val) and val != "" -> String.to_integer(val)
        _ -> 5000
      end

    config = [
      name: connection_name,
      url: url,
      pool_size: pool_size,
      timeout: timeout,
      pool_timeout: pool_timeout,
      idle_interval: 5000,
      backoff_max: 1000,
      backoff_min: 500
    ]

    {Mongo, config}
  end

  defp build_mongo_url(cluster) do
    auth_part =
      if cluster.username && cluster.password do
        "#{cluster.username}:#{cluster.password}@"
      else
        ""
      end

    port = cluster.port || 27017
    db_name = cluster.database_name || "admin"

    auth_source_param =
      if cluster.auth_database && cluster.auth_database != "" do
        "?authSource=#{cluster.auth_database}"
      else
        ""
      end

    "mongodb://#{auth_part}#{cluster.host}:#{port}/#{db_name}#{auth_source_param}"
  end
end
