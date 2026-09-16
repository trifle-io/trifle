defmodule Trifle.Metrics.EscapedPathsPostgresTest do
  use ExUnit.Case, async: true

  alias Trifle.Metrics.Query
  alias Trifle.Stats.{Configuration, Series, Tabler}
  alias Trifle.Stats.Driver.Postgres
  alias TrifleApp.Components.DashboardWidgets.Table

  @at ~U[2026-09-12 10:00:00Z]
  @key "jobs::Trifle.Monitors.Jobs.DispatchRunner"

  test "Postgres writes remain selectable through app queries and dashboard tables" do
    connection_options =
      Trifle.Repo.config()
      |> Keyword.take([:hostname, :port, :username, :password, :database, :socket_dir, :ssl])

    conn = start_supervised!({Postgrex, connection_options})

    # The private connection owns this temporary table; disconnecting removes it.
    # Never create, truncate, or modify the application's real metrics tables.
    Postgrex.query!(
      conn,
      """
      CREATE TEMPORARY TABLE escaped_paths_app (
        key VARCHAR(255) PRIMARY KEY,
        data JSONB NOT NULL DEFAULT '{}'::jsonb
      )
      """,
      []
    )

    config =
      conn
      |> Postgres.new("escaped_paths_app")
      |> Configuration.configure(
        time_zone: "Etc/UTC",
        track_granularities: ["1h"],
        buffer_enabled: false
      )

    input = %{
      "jobs.test.rb.count" => 1,
      ~S(jobs.test\.rb.count) => 2,
      ~S(jobs.\*.count) => 3,
      "jobs.percent%2E.count" => 4
    }

    assert {:ok, _} = Trifle.Stats.track(@key, @at, input, config)
    series = @key |> Trifle.Stats.values(@at, @at, "1h", config) |> Series.new()
    assert [bucket_at] = series.series.at
    assert DateTime.compare(bucket_at, @at) == :eq

    assert series.series.values == [
             %{
               "jobs" => %{
                 "test" => %{"rb" => %{"count" => 1}},
                 "test.rb" => %{"count" => 2},
                 "*" => %{"count" => 3},
                 "percent%2E" => %{"count" => 4}
               }
             }
           ]

    assert Query.available_paths(series) == Enum.sort(Map.keys(input))
    assert Tabler.tabulize(series.series).paths == Enum.sort(Map.keys(input))

    for {path, count} <- input do
      assert {:ok, ^path} = Query.ensure_no_wildcards(path)
      assert Series.aggregate_sum(series, path) == [count]

      widget = %{"id" => "escaped", "type" => "table", "paths" => [path]}
      dataset = Table.dataset(series, widget)
      assert [row] = dataset.rows
      assert dataset.values[{row.path, bucket_at}] == count
    end

    system = Trifle.Stats.values("__system__key__", @at, @at, "1h", config)
    assert [system_values] = system.values
    assert system_values["keys"] == %{@key => 1}

    storage_key = "#{@key}::1h::#{DateTime.to_unix(@at)}"

    assert %{rows: [[physical]]} =
             Postgrex.query!(conn, "SELECT data FROM escaped_paths_app WHERE key = $1", [
               storage_key
             ])

    assert physical == %{
             "jobs.test.rb.count" => 1,
             "jobs.test%2Erb.count" => 2,
             "jobs.%2A.count" => 3,
             "jobs.percent%252E.count" => 4
           }
  end
end
