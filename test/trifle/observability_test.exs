defmodule Trifle.ObservabilityTest do
  use ExUnit.Case, async: true

  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Data.Null, as: NullData

  test "derives a named Postgrex connection from the Ecto Repo options" do
    options =
      Trifle.Observability.stats_connection_options(
        hostname: "postgres",
        port: 5432,
        username: "trifle",
        password: "secret",
        database: "trifle_test",
        socket_options: [:inet6],
        pool_size: 20,
        otp_app: :trifle
      )

    assert options[:name] == Trifle.Observability.StatsPostgres
    assert options[:hostname] == "postgres"
    assert options[:database] == "trifle_test"
    assert options[:socket_options] == [:inet6]
    refute Keyword.has_key?(options, :pool_size)
    refute Keyword.has_key?(options, :otp_app)
  end

  test "uses metadata-only trace storage when no filesystem path is configured" do
    assert %NullData{} =
             Trifle.Observability.trace_data_driver(traces_storage_path: nil)

    assert %NullData{} =
             Trifle.Observability.trace_data_driver(traces_storage_path: "  ")
  end

  test "creates and configures trace filesystem storage" do
    path =
      Path.join(
        System.tmp_dir!(),
        "trifle-observability-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(path) end)

    assert %FileData{path: ^path, gzip: true} =
             Trifle.Observability.trace_data_driver(
               traces_storage_path: path,
               traces_gzip: true
             )

    assert File.dir?(path)
  end

  test "keeps safe searchable Oban metadata without job arguments" do
    job = %{
      id: 42,
      queue: "reports",
      worker: "Trifle.Reports.Generate",
      attempt: 2,
      args: %{"access_token" => "secret"}
    }

    meta = Trifle.Observability.oban_meta(job)

    assert meta == %{
             id: 42,
             queue: "reports",
             worker: "Trifle.Reports.Generate",
             attempt: 2
           }

    refute Map.has_key?(meta, :args)

    assert Trifle.Observability.trace_context(%{meta: meta}) == %{
             queue: "reports",
             worker: "Trifle.Reports.Generate"
           }
  end

  test "cleanup is inert when internal observability is disabled in tests" do
    assert {:ok, 0} = Trifle.Observability.cleanup!()
  end
end
