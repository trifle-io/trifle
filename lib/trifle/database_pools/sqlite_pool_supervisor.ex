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

    case Process.whereis(connection_name) do
      nil ->
        # Start new pool
        child_spec = sqlite_pool_spec(database, connection_name)

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

    case Process.whereis(connection_name) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
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

  defp sqlite_pool_spec(database, connection_name) do
    # SQLite database path - can be file path or :memory:
    database_path = resolve_database_path(database)

    # Extract pool_size from config
    db_config = database.config || %{}
    pool_size = case db_config["pool_size"] do
      nil -> 3  # Smaller default pool for SQLite
      val when is_integer(val) -> val
      val when is_binary(val) -> String.to_integer(val)
    end

    # For SQLite, we'll create a simple GenServer wrapper that manages a single connection
    # since SQLite doesn't benefit from connection pooling the same way as other databases
    
    # Build connection config for direct exqlite usage
    config = [
      name: connection_name,
      database: database_path
    ]

    # Create a simple wrapper process that holds the SQLite connection
    %{
      id: connection_name,
      start: {__MODULE__, :start_sqlite_connection, [connection_name, database_path]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  defp resolve_database_path(database) do
    case database.file_path do
      ":memory:" ->
        # In-memory database
        ":memory:"

      path when is_binary(path) ->
        # File-based database
        # Ensure directory exists
        path
        |> Path.dirname()
        |> File.mkdir_p!()

        path

      _ ->
        # Fallback to a default path based on database ID
        db_dir = Application.get_env(:trifle, :sqlite_db_dir, "/tmp/trifle_sqlite")
        File.mkdir_p!(db_dir)
        Path.join(db_dir, "trifle_db_#{database.id}.sqlite")
    end
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