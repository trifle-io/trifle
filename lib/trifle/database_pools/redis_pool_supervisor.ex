defmodule Trifle.DatabasePools.RedisPoolSupervisor do
  @moduledoc """
  Dynamic supervisor for Redis connections to different databases
  configured in Trifle.Organization.Database records.

  Each database gets its own connection pool with multiple Redix connections
  for load distribution and fault tolerance.
  """

  use DynamicSupervisor

  # Number of Redis connections per pool for load distribution
  @connections_per_pool 5

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new Redis connection pool for a specific database configuration.
  Returns the connection pool name to use for queries.

  ## Examples
      iex> database = %{id: 123, hostname: "localhost", ...}
      iex> {:ok, pool_name} = RedisPoolSupervisor.start_redis_pool(database)
      {:ok, :trifle_redis_pool_123}
  """
  def start_redis_pool(%{id: database_id} = database) do
    pool_name = redis_pool_name(database_id)
    supervisor_name = redis_supervisor_name(database_id)

    case Process.whereis(supervisor_name) do
      nil ->
        # Start new pool supervisor with multiple connections
        child_spec = redis_pool_spec(database, pool_name, supervisor_name)

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, _pid} -> {:ok, pool_name}
          {:error, {:already_started, _pid}} -> {:ok, pool_name}
          error -> error
        end

      _pid ->
        # Pool already exists
        {:ok, pool_name}
    end
  end

  @doc """
  Get connection pool name for a database ID without starting it.
  Returns {:ok, pool_name} if pool exists, {:error, :not_started} otherwise.
  """
  def get_redis_connection(database_id) do
    supervisor_name = redis_supervisor_name(database_id)
    pool_name = redis_pool_name(database_id)

    case Process.whereis(supervisor_name) do
      nil -> {:error, :not_started}
      _pid -> {:ok, pool_name}
    end
  end

  @doc """
  Stop a Redis pool for a database.
  Used when database is deleted or pool needs to be recycled.
  """
  def stop_redis_pool(database_id) do
    supervisor_name = redis_supervisor_name(database_id)

    case Process.whereis(supervisor_name) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Execute a Redis command using the pool for the given database ID.
  Uses random connection selection for load distribution.

  ## Examples
      iex> RedisPoolSupervisor.command(123, ["GET", "key"])
      {:ok, "value"}
  """
  def command(database_id, redis_command) do
    pool_name = redis_pool_name(database_id)
    connection_name = :"#{pool_name}_#{random_index()}"

    case Process.whereis(connection_name) do
      nil -> {:error, :pool_not_found}
      _pid -> Redix.command(connection_name, redis_command)
    end
  end

  @doc """
  List all active Redis pools.
  Returns list of {database_id, pool_name, pid} tuples.
  """
  def list_active_pools do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      # Extract database_id from registered name
      case Process.info(pid, :registered_name) do
        {:registered_name, supervisor_name} ->
          database_id = extract_database_id(supervisor_name)
          pool_name = redis_pool_name(database_id)
          {database_id, pool_name, pid}

        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  # Private functions

  defp redis_pool_name(database_id) do
    :"trifle_redis_pool_#{database_id}"
  end

  defp redis_supervisor_name(database_id) do
    :"trifle_redis_supervisor_#{database_id}"
  end

  defp redis_pool_spec(database, pool_name, supervisor_name) do
    # Create multiple Redix connections for load distribution
    children =
      for index <- 0..(@connections_per_pool - 1) do
        connection_name = :"#{pool_name}_#{index}"

        %{
          id: connection_name,
          start:
            {Redix, :start_link,
             [
               [
                 name: connection_name,
                 host: database.host,
                 port: database.port || 6379,
                 password: database.password,
                 database: database.database_name || 0,
                 socket_opts: socket_options(),
                 # Additional Redix options for reliability
                 sync_connect: true,
                 exit_on_disconnection: true
               ]
             ]}
        }
      end

    # Return supervisor spec for the pool
    %{
      id: supervisor_name,
      type: :supervisor,
      start:
        {Supervisor, :start_link, [children, [strategy: :one_for_one, name: supervisor_name]]}
    }
  end

  defp random_index do
    Enum.random(0..(@connections_per_pool - 1))
  end

  defp socket_options do
    if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [:inet]
  end

  defp extract_database_id(supervisor_name) when is_atom(supervisor_name) do
    supervisor_name
    |> Atom.to_string()
    |> String.replace_prefix("trifle_redis_supervisor_", "")
    |> String.to_integer()
  rescue
    _ -> nil
  end
end
