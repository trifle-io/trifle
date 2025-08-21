defmodule Trifle.Organizations.Database do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  
  @drivers ["redis", "postgres", "mongo", "sqlite"]
  
  schema "databases" do
    field :display_name, :string
    field :driver, :string
    field :host, :string
    field :port, :integer
    field :database_name, :string
    field :file_path, :string
    field :username, :string
    field :password, :string
    field :config, :map, default: %{}
    field :last_check_at, :utc_datetime
    field :last_check_status, :string, default: "pending"
    field :last_error, :string

    timestamps()
  end

  def drivers, do: @drivers

  def default_port("redis"), do: 6379
  def default_port("postgres"), do: 5432
  def default_port("mongo"), do: 27017
  def default_port("sqlite"), do: nil

  def requires_username?("sqlite"), do: false
  def requires_username?(_), do: true

  def requires_password?("sqlite"), do: false
  def requires_password?(_), do: true

  def shows_username?("sqlite"), do: false
  def shows_username?(_), do: true

  def shows_password?("sqlite"), do: false
  def shows_password?(_), do: true

  def requires_host?("sqlite"), do: false
  def requires_host?(_), do: true

  def requires_port?("sqlite"), do: false
  def requires_port?(_), do: true

  def default_config_options("redis") do
    %{
      "pool_size" => 5,
      "pool_timeout" => 5000,
      "timeout" => 5000,
      "prefix" => "trifle_stats",
      "expire_after" => nil
    }
  end

  def default_config_options("postgres") do
    %{
      "pool_size" => 10,
      "pool_timeout" => 15000,
      "timeout" => 15000,
      "ssl" => false,
      "table_name" => "trifle_stats",
      "joined_identifiers" => true
    }
  end

  def default_config_options("mongo") do
    %{
      "pool_size" => 5,
      "pool_timeout" => 5000,
      "timeout" => 5000,
      "collection_name" => "trifle_stats",
      "expire_after" => nil,
      "joined_identifiers" => true
    }
  end

  def default_config_options("sqlite") do
    %{
      "pool_size" => 5,
      "timeout" => 5000,
      "table_name" => "trifle_stats",
      "joined_identifiers" => true
    }
  end

  def default_config_options(_), do: %{}

  @doc false
  def changeset(database, attrs) do
    database
    |> cast(attrs, [:display_name, :driver, :host, :port, :database_name, :file_path, :username, :password, :config, :last_check_at, :last_check_status, :last_error])
    |> validate_required([:display_name, :driver])
    |> validate_inclusion(:driver, @drivers)
    |> validate_conditional_fields()
    |> validate_length(:display_name, min: 1, max: 255)
    |> validate_number(:port, greater_than: 0, less_than: 65536)
    |> put_default_config()
  end

  defp validate_conditional_fields(changeset) do
    driver = get_field(changeset, :driver)
    
    changeset
    |> maybe_validate_required_field(:host, requires_host?(driver))
    |> maybe_validate_required_field(:port, requires_port?(driver))
    |> maybe_validate_required_field(:username, requires_username_for_validation?(driver))
    |> maybe_validate_required_field(:password, requires_password_for_validation?(driver))
    |> maybe_validate_required_field(:database_name, driver != "redis" && driver != "sqlite")
    |> maybe_validate_required_field(:file_path, driver == "sqlite")
  end

  defp requires_username_for_validation?("sqlite"), do: false
  defp requires_username_for_validation?("redis"), do: false
  defp requires_username_for_validation?("mongo"), do: false
  defp requires_username_for_validation?(_), do: true

  defp requires_password_for_validation?("sqlite"), do: false
  defp requires_password_for_validation?("redis"), do: false
  defp requires_password_for_validation?("mongo"), do: false
  defp requires_password_for_validation?(_), do: true

  defp maybe_validate_required_field(changeset, field, true) do
    validate_required(changeset, [field])
  end
  
  defp maybe_validate_required_field(changeset, _field, false), do: changeset

  defp put_default_config(changeset) do
    case get_field(changeset, :driver) do
      nil -> changeset
      driver ->
        config = get_field(changeset, :config) || %{}
        default_config = default_config_options(driver)
        merged_config = Map.merge(default_config, config)
        normalized_config = normalize_config_values(merged_config)
        put_change(changeset, :config, normalized_config)
    end
  end

  # Convert string values to appropriate types
  defp normalize_config_values(config) when is_map(config) do
    config
    |> Enum.map(fn {key, value} -> {key, normalize_config_value(key, value)} end)
    |> Enum.into(%{})
  end

  defp normalize_config_value("ssl", "true"), do: true
  defp normalize_config_value("ssl", "false"), do: false
  defp normalize_config_value("joined_identifiers", "true"), do: true
  defp normalize_config_value("joined_identifiers", "false"), do: false
  defp normalize_config_value(_key, value), do: value

  def stats_config(database) do
    driver = get_or_create_driver(database)
    
    Trifle.Stats.Configuration.configure(
      driver,
      time_zone: "UTC",
      time_zone_database: Tzdata.TimeZoneDatabase,
      beginning_of_week: :monday,
      track_granularities: ["1s", "1m", "1h", "1d", "1w", "1mo", "1q", "1y"]
    )
  end

  # Get or create supervised connection pool for a database
  defp get_or_create_driver(%__MODULE__{driver: "postgres"} = database) do
    {:ok, connection_name} = Trifle.DatabasePools.PostgresPoolSupervisor.start_postgres_pool(database)
    config = database.config || %{}
    
    # Convert joined_identifiers to boolean
    joined_identifiers = case config["joined_identifiers"] do
      nil -> true
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      val -> val
    end
    
    Trifle.Stats.Driver.Postgres.new(
      connection_name,
      config["table_name"] || "trifle_stats",
      joined_identifiers,
      config["ping_table_name"]
    )
  end
  
  defp get_or_create_driver(%__MODULE__{driver: "mongo"} = database) do
    {:ok, connection_name} = Trifle.DatabasePools.MongoPoolSupervisor.start_mongo_pool(database)
    config = database.config || %{}
    
    # Convert joined_identifiers to boolean
    joined_identifiers = case config["joined_identifiers"] do
      nil -> true
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      val -> val
    end
    
    Trifle.Stats.Driver.Mongo.new(
      connection_name,
      config["collection_name"] || "trifle_stats",
      "::",
      1,
      joined_identifiers,
      config["expire_after"]
    )
  end
  
  defp get_or_create_driver(%__MODULE__{driver: "redis"} = database) do
    case Trifle.DatabasePools.RedisPoolSupervisor.start_redis_pool(database) do
      {:ok, pool_name} ->
        config = database.config || %{}
        
        # Use the first connection from the pool as the connection reference
        # The Redis driver will need to be updated to handle pool-based connections
        first_connection_name = :"#{pool_name}_0"
        
        Trifle.Stats.Driver.Redis.new(
          first_connection_name,
          config["prefix"] || "trifle_stats",
          "::"
        )
      {:error, reason} ->
        raise "Failed to start Redis pool: #{inspect(reason)}"
    end
  end
  
  defp get_or_create_driver(%__MODULE__{driver: "sqlite"} = database) do
    {:ok, connection_name} = Trifle.DatabasePools.SqlitePoolSupervisor.start_sqlite_pool(database)
    config = database.config || %{}
    
    # Convert joined_identifiers to boolean
    joined_identifiers = case config["joined_identifiers"] do
      nil -> true
      true -> true
      false -> false
      "true" -> true
      "false" -> false
      val -> val
    end
    
    # Get the actual connection from our wrapper GenServer
    case GenServer.call(connection_name, :get_connection) do
      {:ok, actual_connection} ->
        Trifle.Stats.Driver.Sqlite.new(
          actual_connection,
          config["table_name"] || "trifle_stats",
          config["ping_table_name"],
          joined_identifiers
        )
      {:error, reason} ->
        raise "Failed to get SQLite connection: #{inspect(reason)}"
    end
  end
  
  defp get_or_create_driver(%__MODULE__{driver: "mysql"} = _database) do
    # TODO: Implement MySQL driver in trifle_stats first
    raise ArgumentError, "MySQL driver not yet implemented in trifle_stats library"
  end
  
  defp get_or_create_driver(%__MODULE__{driver: driver}) do
    raise ArgumentError, "Unsupported database driver: #{driver}"
  end

  # Helper functions for URL building (still used in setup/check functions)
  defp build_redis_url(database) do
    url = "redis://"
    url = if database.password, do: "#{url}:#{database.password}@", else: url
    url = "#{url}#{database.host}:#{database.port}"
    url
  end

  defp build_mongo_url(database) do
    url = "mongodb://"
    url = if database.username && database.password do
      "#{url}#{database.username}:#{database.password}@"
    else
      url
    end
    url = "#{url}#{database.host}:#{database.port}/#{database.database_name}"
    url
  end

  def is_setup?(database) do
    case database.last_check_status do
      "success" -> true
      _ -> false
    end
  end

  def check_status(database) do
    try do
      {setup_exists, error_msg} = case database.driver do
        "redis" -> 
          driver = build_driver_for_check(database)
          {redis_exists?(driver), nil}
        "mongo" -> 
          require Logger
          result = mongo_exists_direct?(database)
          Logger.info("MongoDB exists check returned: #{inspect(result)}")
          {result, nil}
        "postgres" -> postgres_exists_direct?(database)
        "sqlite" -> 
          {sqlite_exists_direct?(database), nil}
        _ -> {false, nil}
      end

      status = cond do
        error_msg -> "error"
        setup_exists -> "success"
        true -> "pending"
      end
      
      require Logger
      Logger.info("Setting database status to: #{status} (setup_exists: #{setup_exists}, error: #{inspect(error_msg)})")
      
      # Update the database record with check results
      {:ok, updated_database} = update_check_status(database, status, error_msg)
      
      if error_msg do
        {:error, updated_database, error_msg}
      else
        {:ok, updated_database, setup_exists}
      end
    rescue
      error ->
        error_msg = Exception.message(error)
        {:ok, updated_database} = update_check_status(database, "error", error_msg)
        {:error, updated_database, error_msg}
    end
  end

  defp update_check_status(database, status, error) do
    import Ecto.Changeset
    
    attrs = %{
      last_check_at: DateTime.utc_now(),
      last_check_status: status,
      last_error: error
    }
    
    database
    |> changeset(attrs)
    |> Trifle.Repo.update()
  end

  def setup(database) do
    try do
      config = database.config || %{}
      
      case database.driver do
        "sqlite" ->
          require Logger
          Logger.info("SQLite setup starting for database: #{database.id}")
          
          # First ensure the directory exists
          file_path = database.file_path
          Logger.info("SQLite file path: #{file_path}")
          
          if file_path do
            dir_path = Path.dirname(file_path)
            File.mkdir_p!(dir_path)
            Logger.info("Created directory: #{dir_path}")
          end
          
          # Use our connection pool to get or create the connection
          case Trifle.DatabasePools.SqlitePoolSupervisor.start_sqlite_pool(database) do
            {:ok, connection_name} ->
              table_name = config["table_name"] || "trifle_stats"
              joined_identifiers = case config["joined_identifiers"] do
                "true" -> true
                "false" -> false
                nil -> true
                val -> val
              end
              ping_table_name = config["ping_table_name"]
              
              # Get the actual connection from our wrapper GenServer
              case GenServer.call(connection_name, :get_connection) do
                {:ok, actual_connection} ->
                  # Use the driver's setup function instead of manual table creation
                  try do
                    result = Trifle.Stats.Driver.Sqlite.setup!(actual_connection, table_name, joined_identifiers, ping_table_name)
                    
                    case result do
                      :ok -> {:ok, "SQLite database setup completed successfully"}
                      other -> {:error, "Setup returned unexpected result: #{inspect(other)}"}
                    end
                  rescue
                    error ->
                      error_msg = Exception.message(error)
                      {:error, "SQLite setup failed: #{error_msg}"}
                  end
                  
                {:error, reason} ->
                  {:error, "Failed to get SQLite connection: #{inspect(reason)}"}
              end
              
            {:error, reason} ->
              {:error, "Failed to create SQLite pool: #{inspect(reason)}"}
          end
          
        "redis" ->
          # Redis doesn't need table creation, just verify connection works
          url = build_redis_url(database)
          
          case Redix.start_link(url) do
            {:ok, conn} ->
              # Test the connection by setting and deleting a test key
              test_key = "#{config["prefix"] || "trifle_stats"}::setup_test"
              
              case Redix.command(conn, ["SET", test_key, "test"]) do
                {:ok, "OK"} ->
                  # Clean up test key
                  Redix.command(conn, ["DEL", test_key])
                  GenServer.stop(conn)
                  {:ok, "Redis connection verified successfully"}
                {:error, reason} ->
                  GenServer.stop(conn)
                  {:error, "Redis test command failed: #{inspect(reason)}"}
              end
              
            {:error, reason} ->
              {:error, "Failed to connect to Redis: #{inspect(reason)}"}
          end
          
        "mongo" ->
          # Build MongoDB connection URL
          url = build_mongo_url(database)
          require Logger
          Logger.info("MongoDB setup attempting to connect to: #{url}")
          
          case Mongo.start_link(url: url) do
            {:ok, conn} ->
              Logger.info("MongoDB setup connection successful")
              collection_name = config["collection_name"] || "trifle_stats"
              joined_identifiers = case config["joined_identifiers"] do
                "true" -> true
                "false" -> false
                nil -> true
                val -> val
              end
              expire_after = case config["expire_after"] do
                nil -> nil
                "" -> nil
                val when is_binary(val) -> 
                  case Integer.parse(val) do
                    {num, ""} -> num
                    _ -> nil
                  end
                val when is_integer(val) -> val
              end
              
              # Use the driver's setup function
              Logger.info("MongoDB calling setup! with collection: #{collection_name}, joined: #{joined_identifiers}, expire: #{inspect(expire_after)}")
              result = Trifle.Stats.Driver.Mongo.setup!(conn, collection_name, joined_identifiers, expire_after)
              Logger.info("MongoDB setup! returned: #{inspect(result)}")
              
              # Close the connection after setup
              GenServer.stop(conn)
              
              case result do
                :ok -> {:ok, "MongoDB collection and indexes created successfully"}
                {:error, reason} -> {:error, "MongoDB setup failed: #{inspect(reason)}"}
              end
              
            {:error, reason} ->
              {:error, "Failed to connect to MongoDB: #{inspect(reason)}"}
          end
          
        "postgres" ->
          # Build PostgreSQL connection
          case Postgrex.start_link(
            hostname: database.host,
            port: database.port,
            username: database.username,
            password: database.password,
            database: database.database_name,
            pool_size: 1,
            pool_timeout: 5000,
            timeout: 5000
          ) do
            {:ok, conn} ->
              table_name = config["table_name"] || "trifle_stats"
              joined_identifiers = case config["joined_identifiers"] do
                "true" -> true
                "false" -> false
                nil -> true
                val -> val
              end
              ping_table_name = config["ping_table_name"]
              
              # Use the driver's setup function
              try do
                result = Trifle.Stats.Driver.Postgres.setup!(conn, table_name, joined_identifiers, ping_table_name)
                
                # Close the connection after setup
                GenServer.stop(conn)
                
                case result do
                  :ok -> {:ok, "PostgreSQL tables created successfully"}
                  other -> {:error, "Setup returned unexpected result: #{inspect(other)}"}
                end
              rescue
                error ->
                  GenServer.stop(conn)
                  error_msg = convert_postgres_error_to_friendly_message(error, database)
                  {:error, "PostgreSQL setup failed: #{error_msg}"}
              end
              
            {:error, reason} ->
              error_msg = convert_postgres_error_to_friendly_message(reason, database)
              {:error, "Failed to connect to PostgreSQL: #{error_msg}"}
          end
          
        _ ->
          {:error, "Unsupported database driver: #{database.driver}"}
      end
    rescue
      error -> {:error, "Setup failed: #{Exception.message(error)}"}
    end
  end

  def nuke(database) do
    try do
      driver = build_driver_for_check(database)
      case Trifle.Stats.nuke(driver) do
        :ok -> {:ok, "Database nuked successfully"}
        {:error, reason} -> {:error, "Nuke failed: #{inspect(reason)}"}
      end
    rescue
      error -> {:error, "Nuke failed: #{Exception.message(error)}"}
    end
  end

  defp build_driver_for_check(database) do
    stats_config(database).driver
  end

  defp redis_exists?(driver) do
    # For Redis, we consider it "setup" if we can connect and perform basic operations
    # Redis doesn't need schema setup like SQL databases
    case Redix.command(driver.connection, ["PING"]) do
      {:ok, "PONG"} -> true
      _ -> false
    end
  end

  defp mongo_exists?(driver) do
    # Check if the collection exists by trying to get collection info
    case Mongo.show_collections(driver.connection) do
      {:ok, collections} ->
        collection_names = Enum.map(collections, & &1["name"])
        Enum.member?(collection_names, driver.collection_name)
      _ -> false
    end
  end

  defp mongo_exists_direct?(database) do
    # Direct MongoDB check without creating a driver
    url = build_mongo_url(database)
    config = database.config || %{}
    collection_name = config["collection_name"] || "trifle_stats"
    
    require Logger
    Logger.info("MongoDB status check looking for collection: #{collection_name}")
    
    case Mongo.start_link(url: url, pool_size: 1, timeout: 2000, pool_timeout: 2000) do
      {:ok, conn} ->
        Logger.info("MongoDB status check connection successful")
        # Mongo.show_collections returns a Stream, so we need to enumerate it
        collections_stream = Mongo.show_collections(conn)
        Logger.info("MongoDB show_collections stream: #{inspect(collections_stream)}")
        
        result = try do
          collections = Enum.to_list(collections_stream)
          Logger.info("MongoDB collections enumerated: #{inspect(collections)}")
          
          # Collections are already collection names (strings), not objects with "name" field
          collection_names = collections
          Logger.info("MongoDB found collections: #{inspect(collection_names)}")
          exists = Enum.member?(collection_names, collection_name)
          Logger.info("MongoDB collection #{collection_name} exists: #{exists}")
          exists
        rescue
          error ->
            Logger.error("MongoDB collections enumeration failed: #{inspect(error)}")
            false
        end
        GenServer.stop(conn)
        result
      {:error, reason} -> 
        Logger.error("MongoDB status check connection failed: #{inspect(reason)}")
        false
      _ -> 
        Logger.error("MongoDB status check connection failed with unknown error")
        false
    end
  end

  defp postgres_exists?(driver) do
    query = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = $1)"
    case Postgrex.query(driver.connection, query, [driver.table_name]) do
      {:ok, %{rows: [[true]]}} -> true
      _ -> false
    end
  end

  defp postgres_exists_direct?(database) do
    # Direct PostgreSQL check without creating a driver
    config = database.config || %{}
    table_name = config["table_name"] || "trifle_stats"
    
    require Logger
    Logger.info("PostgreSQL status check attempting to connect to: #{database.host}:#{database.port}/#{database.database_name}")
    
    case Postgrex.start_link(
      hostname: database.host,
      port: database.port,
      username: database.username,
      password: database.password,
      database: database.database_name,
      pool_size: 1,
      pool_timeout: 5000,
      timeout: 5000
    ) do
      {:ok, conn} ->
        Logger.info("PostgreSQL status check connection successful")
        result = try do
          query = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = $1)"
          case Postgrex.query(conn, query, [table_name]) do
            {:ok, %{rows: [[true]]}} -> 
              Logger.info("PostgreSQL table #{table_name} exists: true")
              {true, nil}
            {:ok, %{rows: [[false]]}} -> 
              Logger.info("PostgreSQL table #{table_name} exists: false")
              {false, nil}
            {:error, reason} ->
              Logger.error("PostgreSQL table check query failed: #{inspect(reason)}")
              error_msg = convert_postgres_error_to_friendly_message(reason, database)
              {false, error_msg}
            other ->
              Logger.error("PostgreSQL table check returned unexpected result: #{inspect(other)}")
              error_msg = "Unexpected result: #{inspect(other)}"
              {false, error_msg}
          end
        rescue
          error ->
            Logger.error("PostgreSQL table check failed: #{inspect(error)}")
            error_msg = convert_postgres_error_to_friendly_message(error, database)
            Logger.info("Final error message: #{error_msg}")
            {false, error_msg}
        end
        GenServer.stop(conn)
        result
      {:error, reason} -> 
        Logger.error("PostgreSQL status check connection failed: #{inspect(reason)}")
        error_msg = convert_postgres_error_to_friendly_message(reason, database)
        {false, error_msg}
      _ -> 
        Logger.error("PostgreSQL status check connection failed with unknown error")
        error_msg = "Unable to connect to PostgreSQL database"
        {false, error_msg}
    end
  end

  defp sqlite_exists_direct?(database) do
    # Direct SQLite check without creating a driver
    config = database.config || %{}
    table_name = config["table_name"] || "trifle_stats"
    
    case Trifle.DatabasePools.SqlitePoolSupervisor.start_sqlite_pool(database) do
      {:ok, connection_name} ->
        query = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
        case GenServer.call(connection_name, {:query, query, [table_name]}) do
          {:ok, %{rows: rows}} when length(rows) > 0 -> true
          _ -> false
        end
      {:error, _reason} ->
        false
    end
  end

  defp convert_postgres_error_to_friendly_message(error, database) do
    case error do
      %DBConnection.ConnectionError{reason: :queue_timeout} ->
        "Cannot connect to host '#{database.host}' (connection timeout)"
      %DBConnection.ConnectionError{message: message} when is_binary(message) ->
        cond do
          String.contains?(message, "non-existing domain") or String.contains?(message, "nxdomain") ->
            "Cannot connect to host '#{database.host}' (host not found)"
          String.contains?(message, "connection refused") ->
            "Connection refused by '#{database.host}:#{database.port}' (service not running?)"
          String.contains?(message, "timeout") or String.contains?(message, "queue") ->
            "Cannot connect to host '#{database.host}' (connection timeout)"
          true ->
            "Unable to connect to PostgreSQL database"
        end
      %DBConnection.ConnectionError{} ->
        "Unable to connect to PostgreSQL database"
      %Postgrex.Error{postgres: %{code: :invalid_catalog_name}} ->
        "Database '#{database.database_name}' does not exist"
      %Postgrex.Error{postgres: %{code: :invalid_authorization_specification}} ->
        "Invalid username or password"
      error ->
        # Check if it's a DBConnection error in the message
        message = Exception.message(error)
        cond do
          String.contains?(message, "queue") and String.contains?(message, "timeout") ->
            "Cannot connect to host '#{database.host}' (connection timeout)"
          String.contains?(message, "non-existing domain") or String.contains?(message, "nxdomain") ->
            "Cannot connect to host '#{database.host}' (host not found)"
          String.contains?(message, "connection refused") ->
            "Connection refused by '#{database.host}:#{database.port}' (service not running?)"
          true ->
            "Database query failed: #{message}"
        end
    end
  end
end
