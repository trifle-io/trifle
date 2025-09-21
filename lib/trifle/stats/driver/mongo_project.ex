defmodule Trifle.Stats.Driver.MongoProject do
  @moduledoc """
  MongoDB driver for Trifle.Stats with project-specific reference filtering.

  Extends the base MongoDB driver to include project reference filtering,
  allowing multi-tenant analytics with project isolation.
  """

  defstruct connection: nil,
            reference: nil,
            collection_name: "trifle_stats",
            separator: "::",
            write_concern: 1,
            joined_identifier: true,
            expire_after: nil

  @doc """
  Create a new MongoDB project driver instance.

  ## Parameters
  - `connection`: MongoDB connection
  - `reference`: Project reference/identifier for filtering
  - `collection_name`: Collection name (default: "trifle_stats")
  - `separator`: Key separator for joined mode (default: "::")
  - `write_concern`: Write concern level (default: 1)
  - `joined_identifier`: Use joined (true) or separated (false) identifiers (default: true)
  - `expire_after`: TTL in seconds for automatic document expiration (default: nil)

  ## Examples
      # Basic usage with project reference
      {:ok, conn} = Mongo.start_link(url: "mongodb://localhost:27017/test")
      driver = Trifle.Stats.Driver.MongoProject.new(conn, "project_123")
      
      # With custom options
      driver = Trifle.Stats.Driver.MongoProject.new(conn, "project_123", "analytics", "::", 1, true, 86400)
  """
  def new(
        connection,
        reference,
        collection_name \\ "trifle_stats",
        separator \\ "::",
        write_concern \\ 1,
        joined_identifier \\ true,
        expire_after \\ nil
      ) do
    %Trifle.Stats.Driver.MongoProject{
      connection: connection,
      reference: reference,
      collection_name: collection_name,
      separator: separator,
      write_concern: write_concern,
      joined_identifier: joined_identifier,
      expire_after: expire_after
    }
  end

  @doc """
  Create a new MongoDB project driver from configuration.
  This applies driver_options from the configuration to override defaults.
  """
  def from_config(connection, reference, %Trifle.Stats.Configuration{} = config) do
    # Extract driver options with defaults
    collection_name =
      Trifle.Stats.Configuration.driver_option(config, :collection_name, "trifle_stats")

    joined_identifier = Trifle.Stats.Configuration.driver_option(config, :joined_identifier, true)
    expire_after = Trifle.Stats.Configuration.driver_option(config, :expire_after, nil)

    new(
      connection,
      reference,
      collection_name,
      config.separator,
      1,
      joined_identifier,
      expire_after
    )
  end

  @doc """
  Setup MongoDB collections and indexes with project reference support.

  ## Parameters  
  - `connection`: MongoDB connection
  - `collection_name`: Collection name (default: "trifle_stats")
  - `joined_identifier`: Index strategy - true for joined, false for separated
  - `expire_after`: TTL seconds for automatic expiration (default: nil)

  ## Examples
      # Basic setup (joined identifier mode)
      Trifle.Stats.Driver.MongoProject.setup!(conn)
      
      # Separated mode with TTL
      Trifle.Stats.Driver.MongoProject.setup!(conn, "analytics", false, 86400)
  """
  def setup!(
        connection,
        collection_name \\ "trifle_stats",
        joined_identifier \\ true,
        expire_after \\ nil
      ) do
    # Create the collection
    Mongo.create(connection, collection_name)

    # Create appropriate indexes based on identifier mode, including reference
    indexes =
      if joined_identifier do
        # Joined identifier mode: reference + key fields
        [%{"key" => %{"reference" => 1, "key" => 1}, "unique" => true}]
      else
        # Separated identifier mode: reference + key, range, at fields  
        [%{"key" => %{"reference" => 1, "key" => 1, "range" => 1, "at" => -1}, "unique" => true}]
      end

    # Add TTL index if expire_after is specified
    indexes =
      if expire_after do
        indexes ++ [%{"key" => %{"expire_at" => 1}, "expireAfterSeconds" => 0}]
      else
        indexes
      end

    # Create all indexes
    Mongo.create_indexes(connection, collection_name, indexes)
    :ok
  rescue
    e -> {:error, e}
  end

  @doc """
  Setup from configuration (convenience method).
  """
  def setup_from_config!(connection, %Trifle.Stats.Configuration{} = config) do
    collection_name =
      Trifle.Stats.Configuration.driver_option(config, :collection_name, "trifle_stats")

    joined_identifier = Trifle.Stats.Configuration.driver_option(config, :joined_identifier, true)
    expire_after = Trifle.Stats.Configuration.driver_option(config, :expire_after, nil)

    setup!(connection, collection_name, joined_identifier, expire_after)
  end

  def inc(keys, values, driver) do
    data = Trifle.Stats.Packer.pack(%{data: values})

    bulk =
      Enum.reduce(
        keys,
        Mongo.UnorderedBulk.new(driver.collection_name),
        fn %Trifle.Stats.Nocturnal.Key{} = key, bulk ->
          pkey = Trifle.Stats.Nocturnal.Key.join(key, driver.separator)
          upsert_operation(bulk, "$inc", pkey, driver.reference, data)
        end
      )

    Mongo.BulkWrite.write(driver.connection, bulk, w: driver.write_concern)
  end

  def set(keys, values, driver) do
    # Don't flatten the data - keep it as a nested object to replace entirely
    bulk =
      Enum.reduce(
        keys,
        Mongo.UnorderedBulk.new(driver.collection_name),
        fn %Trifle.Stats.Nocturnal.Key{} = key, bulk ->
          pkey = Trifle.Stats.Nocturnal.Key.join(key, driver.separator)
          # Replace the entire data field with the new values object
          Mongo.UnorderedBulk.update_one(
            bulk,
            %{reference: driver.reference, key: pkey},
            %{"$set" => %{data: values}},
            upsert: true
          )
        end
      )

    Mongo.BulkWrite.write(driver.connection, bulk, w: driver.write_concern)
  end

  def upsert_operation(bulk, operation, pkey, reference, data) do
    Mongo.UnorderedBulk.update_one(
      bulk,
      %{reference: reference, key: pkey},
      %{operation => data},
      upsert: true
    )
  end

  def get(keys, driver) do
    pkeys =
      Enum.map(keys, fn %Trifle.Stats.Nocturnal.Key{} = key ->
        Trifle.Stats.Nocturnal.Key.join(key, driver.separator)
      end)

    map =
      Mongo.find(
        driver.connection,
        driver.collection_name,
        %{reference: driver.reference, key: %{"$in" => pkeys}}
      )
      |> Enum.reduce(%{}, fn d, acc -> Map.merge(acc, %{d["key"] => d["data"]}) end)

    Enum.map(pkeys, fn pkey ->
      raw_data = map[pkey] || %{}
      # If data is stored as nested object, return the data field directly
      case raw_data do
        %{"data" => nested_data} when is_map(nested_data) -> nested_data
        data -> Trifle.Stats.Packer.unpack(data)
      end
    end)
  end

  def ping(%Trifle.Stats.Nocturnal.Key{} = key, values, driver) do
    if driver.joined_identifier do
      []
    else
      # Pack data like Ruby version: { data: values, at: key.at }
      packed_data = Trifle.Stats.Packer.pack(%{data: values, at: key.at})

      # Use reference + key for ping operations
      filter = %{reference: driver.reference, key: key.key}
      update = %{"$set" => packed_data}

      Mongo.update_one(
        driver.connection,
        driver.collection_name,
        filter,
        update,
        upsert: true,
        w: driver.write_concern
      )

      :ok
    end
  end

  def scan(%Trifle.Stats.Nocturnal.Key{} = key, driver) do
    if driver.joined_identifier do
      {nil, %{}}
    else
      # Find the document by reference + key and sort by 'at' descending
      filter = %{reference: driver.reference, key: key.key}
      options = [sort: %{at: -1}, limit: 1]

      case Mongo.find(driver.connection, driver.collection_name, filter, options)
           |> Enum.to_list() do
        [] ->
          {nil, %{}}

        [doc] ->
          # Convert timestamp back to DateTime if it's stored as unix timestamp
          at =
            case doc["at"] do
              timestamp when is_number(timestamp) -> DateTime.from_unix!(timestamp)
              _ -> DateTime.utc_now()
            end

          {at, Trifle.Stats.Packer.unpack(doc)}
      end
    end
  end
end
