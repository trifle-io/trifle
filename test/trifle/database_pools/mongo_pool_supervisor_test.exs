defmodule Trifle.DatabasePools.MongoPoolSupervisorTest do
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.DatabasePools.MongoPoolSupervisor
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Traces.Source.Database, as: TraceDatabase

  defmodule MongoMock do
    use Agent

    def start_link(options) do
      Agent.start_link(fn -> options end, name: options[:name])
    end
  end

  setup do
    previous_client = Application.get_env(:trifle, :mongo_pool_client)
    Application.put_env(:trifle, :mongo_pool_client, MongoMock)

    database =
      database_fixture(%{
        driver: "mongo",
        host: "mongo.example.test",
        port: 27017,
        database_name: "analytics",
        username: "test",
        password: "test",
        trace_config: %{
          "index_name" => "trifle_traces",
          "data_driver" => "file",
          "data_path" => "/tmp/mongo-pool-test-traces",
          "retention_days" => 7,
          "gzip" => false
        }
      })

    on_exit(fn ->
      MongoPoolSupervisor.stop_mongo_pool(database.id)

      if is_nil(previous_client),
        do: Application.delete_env(:trifle, :mongo_pool_client),
        else: Application.put_env(:trifle, :mongo_pool_client, previous_client)
    end)

    %{database: database}
  end

  test "Stats and trace indexes use the same pool with the configured timeouts", %{database: db} do
    {:ok, db} =
      Organizations.update_database(db, %{
        config: %{"pool_size" => 8, "timeout" => 50_000, "pool_timeout" => 45_000}
      })

    stats = Database.stats_config(db)
    traces = TraceDatabase.configuration(db)

    assert stats.driver.connection == traces.index_driver.connection
    options = Agent.get(stats.driver.connection, & &1)
    assert options[:pool_size] == 8
    assert options[:timeout] == 50_000
    assert options[:pool_timeout] == 45_000
  end

  test "saving a timeout change restarts the shared pool with the new timeout", %{database: db} do
    {:ok, connection} = MongoPoolSupervisor.start_mongo_pool(db)
    previous_pid = Process.whereis(connection)
    assert Agent.get(connection, & &1[:timeout]) == 5000

    {:ok, updated} = Organizations.update_database(db, %{config: %{"timeout" => 50_000}})
    assert updated.pool_version > db.pool_version

    traces = TraceDatabase.configuration(updated)
    assert traces.index_driver.connection == connection
    refute Process.whereis(connection) == previous_pid
    assert Agent.get(connection, & &1[:timeout]) == 50_000
    assert Database.stats_config(updated).driver.connection == connection
  end

  test "legacy string settings are passed to the pool as integers", %{database: db} do
    db = %{
      db
      | config: %{"pool_size" => "7", "timeout" => "50000", "pool_timeout" => "40000"}
    }

    {:ok, connection} = MongoPoolSupervisor.start_mongo_pool(db)
    options = Agent.get(connection, & &1)
    assert options[:pool_size] == 7
    assert options[:timeout] == 50_000
    assert options[:pool_timeout] == 40_000
  end

  test "missing and invalid settings retain the default limits without crashing", %{database: db} do
    for value <- [nil, "", 0, -1, "invalid", "50000ms", %{}] do
      db = %{
        db
        | id: Ecto.UUID.generate(),
          config: %{"pool_size" => value, "timeout" => value, "pool_timeout" => value}
      }

      on_exit(fn -> MongoPoolSupervisor.stop_mongo_pool(db.id) end)
      assert {:ok, connection} = MongoPoolSupervisor.start_mongo_pool(db)
      options = Agent.get(connection, & &1)
      assert options[:pool_size] == 5
      assert options[:timeout] == 5000
      assert options[:pool_timeout] == 5000
    end
  end
end
