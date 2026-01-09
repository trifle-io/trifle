defmodule Trifle.Stats.Driver.MongoProject do
  @moduledoc """
  MongoDB driver for Trifle.Stats scoped by project reference.

  Mirrors the core Mongo driver while ensuring every query, index, and
  upsert is filtered by the provided `reference`.
  """

  defstruct connection: nil,
            reference: nil,
            collection_name: "trifle_stats",
            separator: "::",
            write_concern: 1,
            joined_identifier: :partial,
            expire_after: nil,
            system_tracking: true

  @doc """
  Create a new MongoDB project driver instance.
  """
  def new(
        connection,
        reference,
        collection_name \\ "trifle_stats",
        separator \\ "::",
        write_concern \\ 1,
        joined_identifier \\ :partial,
        expire_after \\ nil,
        system_tracking \\ true
      ) do
    identifier_mode = normalize_joined_identifier(joined_identifier)

    %__MODULE__{
      connection: connection,
      reference: reference,
      collection_name: collection_name,
      separator: separator,
      write_concern: write_concern,
      joined_identifier: identifier_mode,
      expire_after: expire_after,
      system_tracking: system_tracking
    }
  end

  @doc """
  Build a driver from configuration.
  """
  def from_config(connection, reference, %Trifle.Stats.Configuration{} = config) do
    collection_name =
      Trifle.Stats.Configuration.driver_option(config, :collection_name, "trifle_stats")

    joined_identifier =
      Trifle.Stats.Configuration.driver_option(config, :joined_identifier, :partial)

    expire_after = Trifle.Stats.Configuration.driver_option(config, :expire_after, nil)
    system_tracking = Trifle.Stats.Configuration.driver_option(config, :system_tracking, true)

    new(
      connection,
      reference,
      collection_name,
      config.separator,
      1,
      joined_identifier,
      expire_after,
      system_tracking
    )
  end

  @doc """
  Setup MongoDB collections and indexes (reference scoped).
  """
  def setup!(
        connection,
        collection_name \\ "trifle_stats",
        joined_identifier \\ :partial,
        expire_after \\ nil,
        _system_tracking \\ true
      ) do
    Mongo.create(connection, collection_name)
    identifier_mode = normalize_joined_identifier(joined_identifier)

    indexes =
      case identifier_mode do
        :full ->
          [%{"key" => %{"reference" => 1, "key" => 1}, "unique" => true}]

        :partial ->
          [%{"key" => %{"reference" => 1, "key" => 1, "at" => -1}, "unique" => true}]

        nil ->
          [
            %{
              "key" => %{"reference" => 1, "key" => 1, "granularity" => 1, "at" => -1},
              "unique" => true
            }
          ]
      end

    indexes =
      if expire_after do
        indexes ++ [%{"key" => %{"expire_at" => 1}, "expireAfterSeconds" => 0}]
      else
        indexes
      end

    Mongo.create_indexes(connection, collection_name, indexes)
    :ok
  rescue
    e -> {:error, e}
  end

  def setup_from_config!(connection, %Trifle.Stats.Configuration{} = config) do
    collection_name =
      Trifle.Stats.Configuration.driver_option(config, :collection_name, "trifle_stats")

    joined_identifier =
      Trifle.Stats.Configuration.driver_option(config, :joined_identifier, :partial)

    expire_after = Trifle.Stats.Configuration.driver_option(config, :expire_after, nil)
    system_tracking = Trifle.Stats.Configuration.driver_option(config, :system_tracking, true)

    setup!(connection, collection_name, joined_identifier, expire_after, system_tracking)
  end

  def inc(keys, values, driver) do
    data = Trifle.Stats.Packer.pack(%{data: values})

    Enum.each(keys, fn %Trifle.Stats.Nocturnal.Key{} = key ->
      filter =
        key
        |> identifier_for(driver)
        |> convert_keys_to_strings()
        |> with_reference_scope(driver)

      expire_at =
        if driver.expire_after, do: DateTime.add(key.at, driver.expire_after, :second), else: nil

      update =
        if expire_at do
          %{"$inc" => data, "$set" => %{expire_at: expire_at}}
        else
          %{"$inc" => data}
        end

      Mongo.update_many(driver.connection, driver.collection_name, filter, update, upsert: true)

      if driver.system_tracking do
        system_filter =
          key
          |> system_identifier_for(driver)
          |> convert_keys_to_strings()
          |> with_reference_scope(driver)

        system_data = system_data_for(key)

        system_update =
          if expire_at do
            %{"$inc" => system_data, "$set" => %{expire_at: expire_at}}
          else
            %{"$inc" => system_data}
          end

        Mongo.update_many(driver.connection, driver.collection_name, system_filter, system_update,
          upsert: true
        )
      end
    end)
  end

  def set(keys, values, driver) do
    packed_data = Trifle.Stats.Packer.pack(values)

    Enum.each(keys, fn %Trifle.Stats.Nocturnal.Key{} = key ->
      filter =
        key
        |> identifier_for(driver)
        |> convert_keys_to_strings()
        |> with_reference_scope(driver)

      expire_at =
        if driver.expire_after, do: DateTime.add(key.at, driver.expire_after, :second), else: nil

      update =
        if expire_at do
          %{"$set" => %{data: packed_data, expire_at: expire_at}}
        else
          %{"$set" => %{data: packed_data}}
        end

      Mongo.update_many(driver.connection, driver.collection_name, filter, update, upsert: true)

      if driver.system_tracking do
        system_filter =
          key
          |> system_identifier_for(driver)
          |> convert_keys_to_strings()
          |> with_reference_scope(driver)

        system_data = system_data_for(key)

        system_update =
          if expire_at do
            %{"$inc" => system_data, "$set" => %{expire_at: expire_at}}
          else
            %{"$inc" => system_data}
          end

        Mongo.update_many(driver.connection, driver.collection_name, system_filter, system_update,
          upsert: true
        )
      end
    end)
  end

  def get(keys, driver) do
    identifiers =
      Enum.map(keys, fn %Trifle.Stats.Nocturnal.Key{} = key ->
        key
        |> identifier_for(driver)
        |> convert_keys_to_strings()
        |> with_reference_scope(driver)
      end)

    data =
      Mongo.find(driver.connection, driver.collection_name, %{"$or" => identifiers})
      |> Enum.reduce(%{}, fn d, acc ->
        temp_key =
          case driver.joined_identifier do
            :full ->
              %Trifle.Stats.Nocturnal.Key{key: d["key"]}

            :partial ->
              %Trifle.Stats.Nocturnal.Key{
                key: d["key"],
                at: parse_timestamp_from_mongo(d["at"])
              }

            nil ->
              %Trifle.Stats.Nocturnal.Key{
                key: d["key"],
                granularity: d["granularity"],
                at: parse_timestamp_from_mongo(d["at"])
              }
          end

        simple_identifier = simple_identifier_for(temp_key, driver)

        Map.put(acc, simple_identifier, d["data"])
      end)

    Enum.map(keys, fn %Trifle.Stats.Nocturnal.Key{} = key ->
      simple_identifier = simple_identifier_for(key, driver)
      Map.get(data, simple_identifier, %{})
    end)
  end

  def ping(%Trifle.Stats.Nocturnal.Key{} = key, values, driver) do
    if driver.joined_identifier do
      []
    else
      packed_data = Trifle.Stats.Packer.pack(%{data: values, at: key.at})

      identifier =
        key
        |> identifier_for(driver)
        |> convert_keys_to_strings()
        |> with_reference_scope(driver)

      filter = Map.take(identifier, ["key", "reference"])
      update = %{"$set" => packed_data}

      expire_at =
        if driver.expire_after, do: DateTime.add(key.at, driver.expire_after, :second), else: nil

      update =
        if expire_at do
          Map.put(update, "$set", Map.merge(update["$set"], %{expire_at: expire_at}))
        else
          update
        end

      Mongo.update_many(driver.connection, driver.collection_name, filter, update, upsert: true)
      :ok
    end
  end

  def scan(%Trifle.Stats.Nocturnal.Key{} = key, driver) do
    if driver.joined_identifier do
      []
    else
      identifier =
        key
        |> identifier_for(driver)
        |> convert_keys_to_strings()
        |> with_reference_scope(driver)

      filter = Map.take(identifier, ["key", "reference"])
      options = [sort: %{at: -1}, limit: 1]

      case Mongo.find(driver.connection, driver.collection_name, filter, options)
           |> Enum.to_list() do
        [] ->
          []

        [doc] ->
          at =
            case doc["at"] do
              timestamp when is_number(timestamp) -> DateTime.from_unix!(timestamp)
              %DateTime{} = dt -> dt
              _ -> DateTime.utc_now()
            end

          unpacked_data =
            Trifle.Stats.Packer.unpack(Map.drop(doc, ["_id", "key", "granularity", "reference"]))

          [at, unpacked_data]
      end
    end
  end

  defp system_identifier_for(%Trifle.Stats.Nocturnal.Key{} = key, driver) do
    system_key = %Trifle.Stats.Nocturnal.Key{
      key: "__system__key__",
      granularity: key.granularity,
      at: key.at
    }

    identifier_for(system_key, driver)
  end

  defp system_data_for(%Trifle.Stats.Nocturnal.Key{} = key) do
    Trifle.Stats.Packer.pack(%{data: %{count: 1, keys: %{key.key => 1}}})
  end

  defp convert_keys_to_strings(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = if is_map(v) and not is_struct(v), do: convert_keys_to_strings(v), else: v
      Map.put(acc, key, value)
    end)
  end

  defp with_reference_scope(filter, driver) do
    Map.put(filter, "reference", driver.reference)
  end

  defp parse_timestamp_from_mongo(timestamp_value) do
    case timestamp_value do
      %DateTime{} = dt ->
        dt

      timestamp when is_integer(timestamp) ->
        DateTime.from_unix!(timestamp)

      time_str when is_binary(time_str) ->
        case DateTime.from_iso8601(time_str) do
          {:ok, dt, _} ->
            dt

          {:error, _} ->
            case Integer.parse(time_str) do
              {value, ""} -> DateTime.from_unix!(value)
              _ -> time_str
            end
        end

      val ->
        val
    end
  end

  defp identifier_for(%Trifle.Stats.Nocturnal.Key{} = key, driver) do
    case driver.joined_identifier do
      :full ->
        Trifle.Stats.Nocturnal.Key.identifier(key, driver.separator)

      :partial ->
        key_without_at = %{key | at: nil}

        key_without_at
        |> Trifle.Stats.Nocturnal.Key.identifier(driver.separator)
        |> maybe_put_at(key.at)

      nil ->
        Trifle.Stats.Nocturnal.Key.identifier(key, nil)
    end
  end

  defp simple_identifier_for(%Trifle.Stats.Nocturnal.Key{} = key, driver) do
    case driver.joined_identifier do
      :full ->
        Trifle.Stats.Nocturnal.Key.simple_identifier(key, driver.separator)

      :partial ->
        key_without_at = %{key | at: nil}

        key_without_at
        |> Trifle.Stats.Nocturnal.Key.simple_identifier(driver.separator)
        |> maybe_put_at(timestamp_for_identifier(key.at))

      nil ->
        Trifle.Stats.Nocturnal.Key.simple_identifier(key, nil)
    end
  end

  defp maybe_put_at(map, nil), do: map
  defp maybe_put_at(map, value), do: Map.put(map, :at, value)

  defp timestamp_for_identifier(nil), do: nil
  defp timestamp_for_identifier(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp timestamp_for_identifier(value), do: value

  defp normalize_joined_identifier(nil), do: nil
  defp normalize_joined_identifier(:full), do: :full
  defp normalize_joined_identifier("full"), do: :full
  defp normalize_joined_identifier(:partial), do: :partial
  defp normalize_joined_identifier("partial"), do: :partial

  defp normalize_joined_identifier(value) do
    raise ArgumentError,
          "joined_identifier must be nil, :full, \"full\", :partial, or \"partial\", got: #{inspect(value)}"
  end
end
