defmodule Trifle.Traces.Source.DatabaseTest do
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Index.Postgres, as: PostgresIndex
  alias Trifle.Traces.Source.Database, as: TraceDatabase
  alias Trifle.Traces.TraceRecord

  test "builds, sets up, and verifies a per-database PostgreSQL/File configuration" do
    suffix = System.unique_integer([:positive])
    stats_table = "trace_source_stats_#{suffix}"
    trace_table = "trace_source_index_#{suffix}"

    trace_path =
      Path.join(System.tmp_dir!(), "trifle-trace-source-#{Ecto.UUID.generate()}")

    organization = organization_fixture()

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "Trace source",
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: Trifle.Repo.config()[:database],
        username: Trifle.Repo.config()[:username],
        password: Trifle.Repo.config()[:password],
        config: %{
          "table_name" => stats_table,
          "joined_identifiers" => "full"
        },
        trace_config: %{
          "index_name" => trace_table,
          "data_driver" => "file",
          "data_path" => trace_path,
          "retention_days" => 7,
          "gzip" => true
        }
      })

    config = TraceDatabase.configuration(database)
    assert %PostgresIndex{table_name: ^trace_table} = config.index_driver
    assert %FileData{path: ^trace_path, gzip: true} = config.data_driver

    try do
      assert {:ok, message} = Organizations.setup_database(database)
      assert message =~ "Trifle Traces"
      assert {:ok, true} = TraceDatabase.check(database)
      assert File.dir?(trace_path)

      assert {:ok, checked, true} = Organizations.check_database_status(database)
      assert checked.last_check_status == "success"

      # Disabling the app's own telemetry must not disable retention for user sources.
      refute Trifle.Observability.enabled?()
      now = DateTime.utc_now()

      expired = %TraceRecord{
        reference: "expired",
        key: "jobs/Example.Worker",
        first_at: DateTime.add(now, -8, :day),
        last_at: DateTime.add(now, -8, :day),
        expires_at: DateTime.add(now, -1, :day)
      }

      current = %{expired | reference: "current", expires_at: DateTime.add(now, 1, :day)}
      PostgresIndex.create(config.index_driver, expired)
      PostgresIndex.create(config.index_driver, current)

      assert {:ok, 1} = Trifle.Observability.cleanup!()
      assert PostgresIndex.find(config.index_driver, expired.reference) == nil

      assert %TraceRecord{reference: "current"} =
               PostgresIndex.find(config.index_driver, current.reference)
    after
      Trifle.Repo.query!("DROP TABLE IF EXISTS #{trace_table}")
      Trifle.Repo.query!("DROP TABLE IF EXISTS #{stats_table}")
      File.rm_rf!(trace_path)
    end
  end
end
