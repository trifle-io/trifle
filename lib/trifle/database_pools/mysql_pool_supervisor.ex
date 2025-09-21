defmodule Trifle.DatabasePools.MySQLPoolSupervisor do
  @moduledoc """
  Dynamic supervisor for MySQL connections to different databases
  configured in Trifle.Organization.Database records.

  Each database gets its own connection pool with independent supervision,
  fault tolerance, and resource management.
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
  Start a new MySQL connection pool for a specific database configuration.
  Returns the connection name to use for queries.

  ## Examples
      iex> database = %{id: 123, hostname: "localhost", ...}
      iex> {:ok, pool_name} = MySQLPoolSupervisor.start_mysql_pool(database)
      {:ok, :trifle_mysql_pool_123}
  """
  def start_mysql_pool(%{id: database_id} = database) do
    connection_name = mysql_connection_name(database_id)

    case Process.whereis(connection_name) do
      nil ->
        # Start new pool
        child_spec = mysql_pool_spec(database, connection_name)

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, _pid} -> {:ok, connection_name}
          {:error, {:already_started, _pid}} -> {:ok, connection_name}
          error -> error
        end

      _pid ->
        # Pool already exists
        {:ok, connection_name}
    end
  end

  @doc """
  Get connection name for a database ID without starting it.
  Returns {:ok, pool_name} if pool exists, {:error, :not_started} otherwise.
  """
  def get_mysql_connection(database_id) do
    connection_name = mysql_connection_name(database_id)

    case Process.whereis(connection_name) do
      nil -> {:error, :not_started}
      _pid -> {:ok, connection_name}
    end
  end

  @doc """
  Stop a MySQL pool for a database.
  Used when database is deleted or pool needs to be recycled.
  """
  def stop_mysql_pool(database_id) do
    connection_name = mysql_connection_name(database_id)

    case Process.whereis(connection_name) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  List all active MySQL pools.
  Returns list of {database_id, pool_name, pid} tuples.
  """
  def list_active_pools do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      # Extract database_id from registered name
      case Process.info(pid, :registered_name) do
        {:registered_name, pool_name} ->
          database_id = extract_database_id(pool_name)
          {database_id, pool_name, pid}

        _ ->
          nil
      end
    end)
    |> Enum.filter(& &1)
  end

  # Private functions

  defp mysql_connection_name(database_id) do
    :"trifle_mysql_pool_#{database_id}"
  end

  defp mysql_pool_spec(database, connection_name) do
    # Extract pool_size from config
    db_config = database.config || %{}

    pool_size =
      case db_config["pool_size"] do
        nil -> 5
        val when is_integer(val) -> val
        val when is_binary(val) -> String.to_integer(val)
      end

    # Build connection config from database record
    config = [
      name: connection_name,
      hostname: database.host,
      port: database.port || 3306,
      username: database.username,
      password: database.password,
      database: database.database_name,
      pool_size: pool_size,
      timeout: 5000,
      pool_timeout: 5000,
      # MySQL-specific options for better reliability and performance
      socket_options: [:inet6],
      # Enable SSL if needed
      ssl: false,
      ssl_opts: [],
      charset: "utf8mb4",
      collation: "utf8mb4_unicode_ci",
      # Connection behavior
      connect_timeout: 5000,
      handshake_timeout: 5000,
      # Use named prepared statements
      prepare: :named,
      # Connection pool configuration
      queue_target: 5000,
      queue_interval: 5000
    ]

    {MyXQL, config}
  end

  defp extract_database_id(pool_name) when is_atom(pool_name) do
    pool_name
    |> Atom.to_string()
    |> String.replace_prefix("trifle_mysql_pool_", "")
    |> String.to_integer()
  rescue
    _ -> nil
  end
end
