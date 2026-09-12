defmodule Trifle.Stats.Driver.MongoProjectTest do
  use ExUnit.Case, async: true

  alias Trifle.Stats.{Configuration, Nocturnal.Key}
  alias Trifle.Stats.Driver.MongoProject

  defmodule ClientMock do
    def update_many(owner, collection, filter, update, options) do
      send(owner, {:update, collection, filter, update, options})
      {:ok, %{}}
    end

    def write(owner, bulk, options) do
      send(owner, {:bulk, bulk, options})
      {:ok, %{}}
    end

    def find(owner, collection, filter, options) do
      send(owner, {:find, collection, filter, options})
      Process.get(:mongo_documents, [])
    end
  end

  @at ~U[2026-01-01 00:00:00Z]
  @key Key.new(key: "Trifle.Jobs.Worker", granularity: "1h", at: @at)
  @input %{~S(jobs.test\.rb) => 2, "jobs.test.rb" => 3, ~S(jobs.\*) => 5}
  @packed %{"data.jobs.test%2Erb" => 2, "data.jobs.test.rb" => 3, "data.jobs.%2A" => 5}

  defp driver(bulk, mode) do
    %{
      MongoProject.new(self(), "project-123")
      | client: ClientMock,
        bulk_writer: ClientMock,
        bulk_write: bulk,
        joined_identifier: mode
    }
  end

  for bulk <- [true, false], mode <- [:full, :partial, nil], operation <- [:inc, :set] do
    test "#{operation} keeps escaped fields and counts reference-scoped (bulk=#{bulk}, mode=#{inspect(mode)})" do
      driver = driver(unquote(bulk), unquote(mode))
      assert %Configuration{} = Configuration.configure(driver, buffer_enabled: false)
      apply(MongoProject, unquote(operation), [[@key], @input, driver, 7, "Original.Job"])

      updates =
        if unquote(bulk) do
          assert_received {:bulk, %{coll: "trifle_stats", updates: updates}, [w: 1]}
          updates
        else
          for _ <- 1..2 do
            assert_received {:update, "trifle_stats", filter, update, options}
            {filter, update, options}
          end
        end

      assert length(updates) == 2

      for {filter, _, options} <- updates do
        assert filter["reference"] == "project-123"
        assert options[:upsert]
      end

      {_, data, _} =
        Enum.find(updates, fn {filter, _, _} ->
          String.starts_with?(filter["key"], "Trifle.Jobs.Worker")
        end)

      assert data == %{if(unquote(operation) == :inc, do: "$inc", else: "$set") => @packed}

      {_, system, _} =
        Enum.find(updates, fn {filter, _, _} ->
          String.starts_with?(filter["key"], "__system__key__")
        end)

      assert system == %{"$inc" => %{"data.count" => 7, "data.keys.Original%2EJob" => 7}}
    end
  end

  test "reads nested Mongo fields exactly once without decoding payload strings" do
    driver = driver(false, :full)

    Process.put(:mongo_documents, [
      %{
        "key" => Key.join(@key, "::"),
        "reference" => driver.reference,
        "data" => %{"jobs" => %{"test%2Erb" => 2, "%2A" => 5, "test%252Erb" => "%2E"}}
      }
    ])

    assert MongoProject.get([@key], driver) == [
             %{"jobs" => %{"test.rb" => 2, "*" => 5, "test%2Erb" => "%2E"}}
           ]

    assert_received {:find, _, %{"$or" => [filter]}, _}
    assert filter["reference"] == driver.reference
  end

  test "beam and scan preserve escaped names and project scope" do
    driver = driver(false, nil)
    key = %Key{key: "status.job", at: @at}
    assert :ok = MongoProject.ping(key, @input, driver)
    assert_received {:update, _, filter, %{"$set" => fields}, _}
    assert filter == %{"key" => "status.job", "reference" => driver.reference}
    assert Map.drop(fields, ["at"]) == @packed

    Process.put(:mongo_documents, [
      %{
        "key" => key.key,
        "reference" => driver.reference,
        "at" => @at,
        "data" => %{"jobs" => %{"test%2Erb" => 2, "%2A" => 5}}
      }
    ])

    assert [@at, %{"data" => %{"jobs" => %{"test.rb" => 2, "*" => 5}}}] =
             MongoProject.scan(key, driver)

    assert_received {:find, _, ^filter, _}
  end
end
