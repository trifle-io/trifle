defmodule Trifle.DatabasePools.SqlitePoolSupervisor do
  @moduledoc """
  Dynamic supervisor for SQLite connections to different databases
  configured in Trifle.Organization.Database records.

  Each database gets its own connection pool with independent supervision,
  fault tolerance, and resource management.

  Note: SQLite has different connection semantics than other databases
  since it's file-based and has limited concurrent write capabilities.
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
  Start a new SQLite connection pool for a specific database configuration.
  Returns the connection name to use for queries.

  ## Examples
      iex> database = %{id: 123, database: "/path/to/db.sqlite", ...}
      iex> {:ok, pool_name} = SqlitePoolSupervisor.start_sqlite_pool(database)
      {:ok, :trifle_sqlite_pool_123}
  """
  def start_sqlite_pool(%{id: database_id} = database) do
    connection_name = sqlite_connection_name(database_id)
    expected_version = pool_version(database)

    case Process.whereis(connection_name) do
      nil ->
        start_new_sqlite_pool(database, connection_name, expected_version)

      _pid ->
        case Trifle.DatabasePools.VersionRegistry.get(:sqlite, database_id) do
          {:ok, ^expected_version} ->
            {:ok, connection_name}

          _ ->
            _ = stop_sqlite_pool(database_id)
            start_new_sqlite_pool(database, connection_name, expected_version)
        end
    end
  end

  @doc """
  Get connection name for a database ID without starting it.
  Returns {:ok, pool_name} if pool exists, {:error, :not_started} otherwise.
  """
  def get_sqlite_connection(database_id) do
    connection_name = sqlite_connection_name(database_id)

    case Process.whereis(connection_name) do
      nil -> {:error, :not_started}
      _pid -> {:ok, connection_name}
    end
  end

  @doc """
  Stop a SQLite pool for a database.
  Used when database is deleted or pool needs to be recycled.
  """
  def stop_sqlite_pool(database_id) do
    connection_name = sqlite_connection_name(database_id)

    result =
      case Process.whereis(connection_name) do
        nil -> :ok
        pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      end

    _ = Trifle.DatabasePools.VersionRegistry.delete(:sqlite, database_id)

    result
  end

  @doc """
  Execute a SQLite query using the pool for the given database ID.

  ## Examples
      iex> SqlitePoolSupervisor.query(123, "SELECT * FROM users", [])
      {:ok, %{rows: [...], columns: [...]}}
  """
  def query(database_id, sql, params \\ []) do
    connection_name = sqlite_connection_name(database_id)

    case Process.whereis(connection_name) do
      nil -> {:error, :pool_not_found}
      _pid -> GenServer.call(connection_name, {:query, sql, params})
    end
  end

  @doc """
  List all active SQLite pools.
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

  @doc """
  Start a SQLite connection wrapper process.
  This creates a simple GenServer that holds the SQLite connection.
  """
  def start_sqlite_connection(name, database_path) do
    GenServer.start_link(__MODULE__.ConnectionWrapper, database_path, name: name)
  end

  # Private functions

  defp sqlite_connection_name(database_id) do
    :"trifle_sqlite_pool_#{database_id}"
  end

  defp start_new_sqlite_pool(database, connection_name, expected_version) do
    case sqlite_pool_spec(database, connection_name) do
      {:ok, child_spec} ->
        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, _pid} ->
            _ = Trifle.DatabasePools.VersionRegistry.put(:sqlite, database.id, expected_version)
            {:ok, connection_name}

          {:error, {:already_started, _pid}} ->
            reconcile_existing_pool(database, connection_name, expected_version)

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pool_version(database) do
    case Map.get(database, :pool_version) do
      version when is_integer(version) and version > 0 -> version
      _ -> 1
    end
  end

  defp sqlite_pool_spec(database, connection_name) do
    # SQLite database path - can be file path or :memory:
    with {:ok, database_path} <- resolve_database_path(database) do
      # Extract pool_size from config
      db_config = database.config || %{}

      _pool_size =
        case db_config["pool_size"] do
          # Smaller default pool for SQLite
          nil ->
            3

          val when is_integer(val) ->
            val

          val when is_binary(val) ->
            case Integer.parse(val) do
              {parsed, ""} -> parsed
              _ -> 3
            end

          _ ->
            3
        end

      # For SQLite, we'll create a simple GenServer wrapper that manages a single connection
      # since SQLite doesn't benefit from connection pooling the same way as other databases

      # Build connection config for direct exqlite usage
      _config = [
        name: connection_name,
        database: database_path
      ]

      # Create a simple wrapper process that holds the SQLite connection
      {:ok,
       %{
         id: connection_name,
         start: {__MODULE__, :start_sqlite_connection, [connection_name, database_path]},
         type: :worker,
         restart: :permanent,
         shutdown: 5000
       }}
    end
  end

  defp reconcile_existing_pool(database, connection_name, expected_version) do
    case Trifle.DatabasePools.VersionRegistry.get(:sqlite, database.id) do
      {:ok, actual_version} ->
        _ = Trifle.DatabasePools.VersionRegistry.put(:sqlite, database.id, actual_version)

        if actual_version == expected_version do
          {:ok, connection_name}
        else
          _ = stop_sqlite_pool(database.id)
          start_new_sqlite_pool(database, connection_name, expected_version)
        end

      :error ->
        _ = stop_sqlite_pool(database.id)
        start_new_sqlite_pool(database, connection_name, expected_version)
    end
  end

  defp resolve_database_path(database) do
    Trifle.SqliteUploads.resolve_database_path(database)
  end

  defp extract_database_id(pool_name) when is_atom(pool_name) do
    pool_name
    |> Atom.to_string()
    |> String.replace_prefix("trifle_sqlite_pool_", "")
    |> String.to_integer()
  rescue
    _ -> nil
  end

  defmodule ConnectionWrapper do
    @moduledoc """
    Simple GenServer wrapper for SQLite connections.
    SQLite doesn't benefit from traditional connection pooling since it's file-based,
    so we just hold a single connection per database.
    """
    use GenServer

    def start_link(database_path) do
      GenServer.start_link(__MODULE__, database_path)
    end

    def init(database_path) do
      case Exqlite.start_link(database: database_path) do
        {:ok, conn} -> {:ok, conn}
        error -> {:stop, error}
      end
    end

    def handle_call({:query, sql, params}, _from, conn) do
      result = Exqlite.query(conn, sql, params)
      {:reply, result, conn}
    end

    def handle_call(:get_connection, _from, conn) do
      {:reply, {:ok, conn}, conn}
    end

    def handle_call(:connection, _from, conn) do
      {:reply, conn, conn}
    end

    # Handle unexpected DBConnection messages gracefully
    def handle_info({:db_connection, _from, _message}, conn) do
      # Ignore DBConnection messages since we're not using DBConnection for SQLite
      {:noreply, conn}
    end

    def handle_info(_message, conn) do
      # Ignore other unexpected messages
      {:noreply, conn}
    end

    def terminate(_reason, conn) do
      if conn do
        GenServer.stop(conn)
      end

      :ok
    end
  end
end
