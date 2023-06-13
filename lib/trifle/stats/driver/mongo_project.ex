defmodule Trifle.Stats.Driver.MongoProject do
  defstruct connection: nil, reference: nil, collection_name: "trifle_stats", separator: "::", write_concern: 1

  def new(connection, project) do
    %Trifle.Stats.Driver.MongoProject{connection: connection, reference: project}
  end

  def setup!(connection, collection_name: "trifle_stats") do
    # TODO: Implement
  end

  def inc(keys, values, driver) do
    data = Trifle.Stats.Packer.pack(%{data: values})

    bulk = Enum.reduce(keys, Mongo.UnorderedBulk.new(driver.collection_name), fn (key, bulk) ->
      bulk = upsert_operation(bulk, "$inc", Enum.join(key, driver.separator), driver.reference, data)
    end)

    Mongo.BulkWrite.write(driver.connection, bulk, w: driver.write_concern)
  end

  def set(keys, values, driver) do
    data = Trifle.Stats.Packer.pack(%{data: values})
    bulk = Enum.reduce(keys, Mongo.UnorderedBulk.new(driver.collection_name), fn (key, bulk) ->
      bulk = upsert_operation(bulk, "$inc", Enum.join(key, driver.separator), driver.reference, data)
    end)
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
    pkeys = Enum.map(keys, fn k -> Enum.join(k, driver.separator) end)

    map = Mongo.find(
      driver.connection, driver.collection_name, %{reference: driver.reference, key: %{"$in" => pkeys}}
    )
    |> Enum.reduce(%{}, fn(d, acc) -> Map.merge(acc, %{d["key"] => d["data"]}) end)

    Enum.map(pkeys, fn pkey -> map[pkey] || %{} end)
  end
end
