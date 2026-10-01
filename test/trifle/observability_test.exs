defmodule Trifle.ObservabilityTest do
  use ExUnit.Case, async: true

  alias Trifle.Traces.Driver.Data.File, as: FileData
  alias Trifle.Traces.Driver.Data.Null, as: NullData
  alias Trifle.Traces.Driver.Data.S3, as: S3Data

  defmodule FakeS3 do
    def put_lifecycle(test_pid, bucket, rules) do
      send(test_pid, {:put_lifecycle, bucket, rules})
      :ok
    end
  end

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

  test "requires a path for explicit filesystem storage" do
    assert_raise ArgumentError, ~r/TRIFLE_TRACES_STORAGE_PATH is required/, fn ->
      Trifle.Observability.trace_data_driver(
        traces_storage_backend: :file,
        traces_storage_path: nil
      )
    end
  end

  test "configures S3 storage and its retention lifecycle" do
    test_pid = self()

    assert %S3Data{
             adapter: FakeS3,
             buckets: ["traces-a", "traces-b"],
             prefix: "internal",
             gzip: true,
             client: ^test_pid
           } =
             Trifle.Observability.trace_data_driver(
               traces_storage_backend: :s3,
               traces_retention_days: 14,
               traces_gzip: true,
               traces_s3: [
                 adapter: FakeS3,
                 client: test_pid,
                 buckets: ["traces-a", "traces-b"],
                 prefix: "internal"
               ]
             )

    assert_receive {:put_lifecycle, "traces-a", [rule]}
    assert_receive {:put_lifecycle, "traces-b", [^rule]}
    assert rule.id == "trifle-traces-14d"
    assert rule.filter.prefix == "14/internal/"
  end

  test "configured filesystem storage cleans uploaded sources after successful wrapup" do
    root =
      Path.join(System.tmp_dir!(), "trifle-trace-upload-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    source = Path.join(root, "source.txt")
    File.write!(source, "report")

    data =
      Trifle.Observability.trace_data_driver(
        traces_storage_backend: :file,
        traces_storage_path: Path.join(root, "storage"),
        traces_gzip: true
      )

    config =
      Trifle.Traces.Configuration.new(
        index_driver: Trifle.Traces.Driver.Index.Memory.new(),
        data_driver: data,
        bump_every: 0
      )

    {:ok, tracer} = Trifle.Traces.start_tracer("jobs/upload", config: config)
    Trifle.Traces.artifact("public.txt", source, tracer: tracer)
    assert File.exists?(source)
    final = Trifle.Traces.wrapup(tracer: tracer)

    refute File.exists?(source)
    record = Trifle.Traces.find(final.reference, config: config)
    assert record.bucket_name == nil
    assert Trifle.Traces.read_artifact(record, "public.txt", config: config) == "report"
  end

  test "builds ExAws client overrides for an S3-compatible endpoint" do
    assert Trifle.Observability.s3_client_options(
             endpoint: "http://minio:9000",
             region: "us-east-1",
             access_key_id: "minio",
             secret_access_key: "miniosecret"
           ) == [
             access_key_id: "minio",
             secret_access_key: "miniosecret",
             region: "us-east-1",
             http_opts: [with_body: true],
             scheme: "http://",
             host: "minio",
             port: 9000
           ]
  end

  test "disabled observability starts no internal connection or tracing handler" do
    refute Trifle.Observability.enabled?()
    assert Trifle.Observability.setup() == []
    assert Process.whereis(Trifle.Observability.StatsPostgres) == nil
    assert {:error, :observability_disabled} = Trifle.Observability.database_attrs()
  end
end
