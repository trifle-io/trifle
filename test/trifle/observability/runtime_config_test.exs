defmodule Trifle.Observability.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_path Path.expand("../../../config/runtime.exs", __DIR__)
  @moduletag :tmp_dir

  setup do
    env_keys = ~w(DOTENV_PATH TRIFLE_OBSERVABILITY_ENABLED DATABASE_URL SECRET_KEY_BASE
                  TRIFLE_DB_ENCRYPTION_KEY MAILER_ADAPTER TRIFLE_TRACES_GZIP
                  TRIFLE_TRACES_S3_SECRET_ACCESS_KEY TRIFLE_OBSERVABILITY_INDEX_BACKEND
                  TRIFLE_OBSERVABILITY_GRANULARITIES
                  TRIFLE_OBSERVABILITY_DEFAULT_TIMEFRAME
                  TRIFLE_OBSERVABILITY_DEFAULT_GRANULARITY
                  TRIFLE_OBSERVABILITY_TIME_ZONE
                  TRIFLE_OBSERVABILITY_MONGODB_URL MONGODB_URL
                  TRIFLE_TRACES_STORAGE_BACKEND TRIFLE_TRACES_STORAGE_PATH
                  TRIFLE_TRACES_S3_BUCKETS
                  TRIFLE_TRACES_S3_ENDPOINT TRIFLE_TRACES_S3_REGION
                  TRIFLE_TRACES_S3_ACCESS_KEY_ID TRIFLE_TRACES_S3_PREFIX
                  TRIFLE_TRACES_MANAGE_S3_LIFECYCLE)
    previous_env = Map.new(env_keys, &{&1, System.get_env(&1)})
    previous_config = Application.fetch_env!(:trifle, Trifle.Observability)

    on_exit(fn ->
      Enum.each(previous_env, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)

      Application.put_env(:trifle, Trifle.Observability, previous_config)
    end)

    System.delete_env("DOTENV_PATH")
    System.delete_env("TRIFLE_OBSERVABILITY_ENABLED")

    Enum.each(
      ~w(TRIFLE_OBSERVABILITY_INDEX_BACKEND TRIFLE_OBSERVABILITY_MONGODB_URL MONGODB_URL
         TRIFLE_OBSERVABILITY_GRANULARITIES TRIFLE_OBSERVABILITY_DEFAULT_TIMEFRAME
         TRIFLE_OBSERVABILITY_DEFAULT_GRANULARITY TRIFLE_OBSERVABILITY_TIME_ZONE
         TRIFLE_TRACES_STORAGE_BACKEND TRIFLE_TRACES_STORAGE_PATH TRIFLE_TRACES_S3_BUCKETS
         TRIFLE_TRACES_S3_ENDPOINT
         TRIFLE_TRACES_S3_REGION TRIFLE_TRACES_S3_ACCESS_KEY_ID TRIFLE_TRACES_S3_PREFIX
         TRIFLE_TRACES_MANAGE_S3_LIFECYCLE),
      &System.delete_env/1
    )

    System.put_env("DATABASE_URL", "ecto://postgres:postgres@postgres/trifle_test")
    System.put_env("SECRET_KEY_BASE", String.duplicate("test", 16))
    System.put_env("TRIFLE_DB_ENCRYPTION_KEY", Base.encode64(String.duplicate("0", 32)))
    System.put_env("MAILER_ADAPTER", "local")
    Application.put_env(:trifle, Trifle.Observability, enabled: true)
    :ok
  end

  test "development and production accept explicit on/off values", %{tmp_dir: dir} do
    for env <- [:dev, :prod],
        {values, expected} <- [
          {~w(true 1 yes on enabled TRUE), true},
          {~w(false 0 no off disabled FALSE), false}
        ],
        value <- values do
      System.put_env("TRIFLE_OBSERVABILITY_ENABLED", " #{value} ")
      assert enabled_config(dir, env) == expected
    end
  end

  test "missing, empty, and invalid values retain the configured default", %{tmp_dir: dir} do
    for default <- [true, false], env <- [:dev, :prod], value <- [nil, "", "  ", "typo"] do
      Application.put_env(:trifle, Trifle.Observability, enabled: default)

      if is_nil(value),
        do: System.delete_env("TRIFLE_OBSERVABILITY_ENABLED"),
        else: System.put_env("TRIFLE_OBSERVABILITY_ENABLED", value)

      assert enabled_config(dir, env) == default
    end
  end

  test "development reads the flag from .env and .env.local overrides it", %{tmp_dir: dir} do
    Code.ensure_loaded!(Dotenvy)
    File.write!(Path.join(dir, ".env"), "TRIFLE_OBSERVABILITY_ENABLED=false\n")
    refute enabled_config(dir, :dev)

    File.write!(Path.join(dir, ".env.local"), "TRIFLE_OBSERVABILITY_ENABLED=true\n")
    assert enabled_config(dir, :dev)
  end

  test "tests stay disabled even when the development .env enables observability", %{tmp_dir: dir} do
    Code.ensure_loaded!(Dotenvy)
    System.put_env("TRIFLE_OBSERVABILITY_ENABLED", "true")
    refute enabled_config(dir, :test)

    File.write!(Path.join(dir, ".env"), "TRIFLE_OBSERVABILITY_ENABLED=true\n")
    refute enabled_config(dir, :test)
  end

  test "internal Stats granularities and source defaults are configurable", %{tmp_dir: dir} do
    previous_stats = Application.get_env(:trifle_stats, :global_config)
    previous_traces = Application.get_env(:trifle_traces, :configuration)

    on_exit(fn ->
      restore_application_env(:trifle_stats, :global_config, previous_stats)
      restore_application_env(:trifle_traces, :configuration, previous_traces)
    end)

    config = observability_config(dir, :prod)
    assert config[:granularities] == ["1m", "1h", "1d", "1mo"]
    assert config[:default_timeframe] == "6h"
    assert config[:default_granularity] == "1m"
    assert config[:time_zone] == "UTC"

    System.put_env("TRIFLE_OBSERVABILITY_GRANULARITIES", "5m, 6h\n1d")
    System.put_env("TRIFLE_OBSERVABILITY_DEFAULT_TIMEFRAME", "24h")
    System.put_env("TRIFLE_OBSERVABILITY_DEFAULT_GRANULARITY", "6h")
    System.put_env("TRIFLE_OBSERVABILITY_TIME_ZONE", "Asia/Dubai")

    config = observability_config(dir, :prod)
    assert config[:granularities] == ["5m", "6h", "1d"]
    assert config[:default_timeframe] == "24h"
    assert config[:default_granularity] == "6h"
    assert config[:time_zone] == "Asia/Dubai"

    config =
      config
      |> Keyword.put(:traces_storage_backend, :file)
      |> Keyword.put(:traces_storage_path, Path.join(dir, "traces"))

    Application.put_env(:trifle, Trifle.Observability, config)
    assert {:ok, attrs} = Trifle.Observability.database_attrs()
    assert attrs.granularities == ["5m", "6h", "1d"]
    assert attrs.default_timeframe == "24h"
    assert attrs.default_granularity == "6h"
    assert attrs.time_zone == "Asia/Dubai"

    assert [_stats_connection, _traces] = Trifle.Observability.setup()
    assert Trifle.Stats.Configuration.get_global().granularities == ["5m", "6h", "1d"]
    assert Trifle.Stats.Configuration.get_global().time_zone == "Asia/Dubai"
  end

  test "invalid or empty granularities use safe defaults and keep the source selection valid" do
    assert Trifle.Observability.granularities(granularities: ["nope", "0m"]) ==
             ["1m", "1h", "1d", "1mo"]

    assert Trifle.Observability.time_zone(time_zone: "Mars/Olympus") == "UTC"

    Application.put_env(:trifle, Trifle.Observability,
      enabled: true,
      granularities: ["1h", "1d"],
      default_granularity: "1m",
      traces_storage_backend: :file,
      traces_storage_path: "/tmp/trifle-observability-test"
    )

    assert {:ok, attrs} = Trifle.Observability.database_attrs()
    assert attrs.granularities == ["1h", "1d"]
    assert attrs.default_granularity == "1h"
  end

  test "gzip accepts explicit boolean values and preserves defaults for typos", %{tmp_dir: dir} do
    for default <- [true, false], env <- [:dev, :prod] do
      Application.put_env(:trifle, Trifle.Observability, traces_gzip: default)

      for {values, expected} <- [
            {~w(true 1 yes on enabled TRUE), true},
            {~w(false 0 no off disabled FALSE), false},
            {["", "  ", "treu"], default}
          ],
          value <- values do
        System.put_env("TRIFLE_TRACES_GZIP", value)
        assert observability_config(dir, env)[:traces_gzip] == expected
      end

      System.delete_env("TRIFLE_TRACES_GZIP")
      assert observability_config(dir, env)[:traces_gzip] == default
    end

    Application.put_env(:trifle, Trifle.Observability, [])
    System.put_env("TRIFLE_TRACES_GZIP", "treu")
    assert observability_config(dir, :prod)[:traces_gzip]
  end

  test "development S3 secret is supplied by the environment, not a source fallback" do
    path = Path.expand("../../../config/dev.exs", __DIR__)

    for value <- [nil, "local-test-secret"] do
      if is_nil(value),
        do: System.delete_env("TRIFLE_TRACES_S3_SECRET_ACCESS_KEY"),
        else: System.put_env("TRIFLE_TRACES_S3_SECRET_ACCESS_KEY", value)

      config = Config.Reader.read!(path, env: :dev, target: :host)

      assert get_in(config, [:trifle, Trifle.Observability, :traces_s3, :secret_access_key]) ==
               value
    end
  end

  test "MongoDB observability and shared S3 payload settings are loaded from the environment",
       %{tmp_dir: dir} do
    previous_stats = Application.get_env(:trifle_stats, :global_config)
    previous_traces = Application.get_env(:trifle_traces, :configuration)

    on_exit(fn ->
      restore_application_env(:trifle_stats, :global_config, previous_stats)
      restore_application_env(:trifle_traces, :configuration, previous_traces)
    end)

    System.put_env("TRIFLE_OBSERVABILITY_INDEX_BACKEND", "mongo")

    System.put_env(
      "MONGODB_URL",
      "mongodb://trace_user:p%40ss@mongo.example:27018/trifle_production?authSource=admin"
    )

    System.put_env("TRIFLE_TRACES_STORAGE_BACKEND", "s3")
    System.put_env("TRIFLE_TRACES_S3_ENDPOINT", "https://object.example")
    System.put_env("TRIFLE_TRACES_S3_BUCKETS", "uploads")
    System.put_env("TRIFLE_TRACES_S3_REGION", "eu-central")
    System.put_env("TRIFLE_TRACES_S3_ACCESS_KEY_ID", "access")
    System.put_env("TRIFLE_TRACES_S3_SECRET_ACCESS_KEY", "secret")
    System.put_env("TRIFLE_TRACES_S3_PREFIX", "traces")
    System.put_env("TRIFLE_TRACES_MANAGE_S3_LIFECYCLE", "false")

    config = observability_config(dir, :prod)
    assert config[:index_backend] == :mongo
    assert config[:mongodb_url] == System.fetch_env!("MONGODB_URL")
    assert config[:traces_storage_backend] == :s3
    assert config[:traces_s3][:buckets] == ["uploads"]
    assert config[:traces_s3][:prefix] == "traces"
    refute config[:traces_manage_s3_lifecycle]

    Application.put_env(:trifle, Trifle.Observability, config)
    assert {:ok, attrs} = Trifle.Observability.database_attrs()
    assert attrs.driver == "mongo"
    assert attrs.host == "mongo.example"
    assert attrs.port == 27_018
    assert attrs.database_name == "trifle_production"
    assert attrs.username == "trace_user"
    assert attrs.password == "p@ss"
    assert attrs.auth_database == "admin"
    assert attrs.config["collection_name"] == "trifle_internal_stats"
    assert attrs.trace_config["index_name"] == "trifle_internal_traces"
    assert attrs.trace_config["data_driver"] == "s3"
    assert attrs.trace_config["data_buckets"] == ["uploads"]
    assert attrs.trace_config["data_prefix"] == "traces"

    assert [mongo_child, {Trifle.Observability.MongoSetup, _}, traces_child] =
             Trifle.Observability.setup()

    assert mongo_child.id == Trifle.Observability.Mongo
    assert traces_child.id == Trifle.Traces.Oban

    assert %Trifle.Stats.Driver.Mongo{connection: Trifle.Observability.Mongo} =
             Trifle.Stats.Configuration.get_global().driver

    assert %Trifle.Traces.Driver.Index.Mongo{connection: Trifle.Observability.Mongo} =
             Trifle.Traces.configuration().index_driver

    changeset =
      Trifle.Organizations.Database.managed_changeset(
        %Trifle.Organizations.Database{},
        Map.put(attrs, :organization_id, Ecto.UUID.generate()),
        "internal_trifle_observability"
      )

    assert changeset.errors == []
  end

  test "Ecto URL configuration is already normalized for both observability consumers" do
    previous_repo = Application.fetch_env!(:trifle, Trifle.Repo)
    on_exit(fn -> Application.put_env(:trifle, Trifle.Repo, previous_repo) end)

    Application.put_env(:trifle, Trifle.Repo,
      url: "ecto://url_user:p%40ss@url-postgres:5433/url_db?ssl=true",
      pool_size: 20
    )

    Application.put_env(:trifle, Trifle.Observability,
      enabled: true,
      traces_storage_backend: :file,
      traces_storage_path: "/tmp/url-test-traces"
    )

    repo = Trifle.Repo.config()
    refute Keyword.has_key?(repo, :url)
    options = Trifle.Observability.stats_connection_options()
    assert options[:hostname] == "url-postgres"
    assert options[:port] == 5433
    assert options[:username] == "url_user"
    assert options[:password] == "p@ss"
    assert options[:database] == "url_db"
    assert options[:ssl]
    refute Keyword.has_key?(options, :pool_size)

    assert {:ok, attrs} = Trifle.Observability.database_attrs()
    assert attrs.host == options[:hostname]
    assert attrs.port == options[:port]
    assert attrs.username == options[:username]
    assert attrs.password == options[:password]
    assert attrs.database_name == options[:database]
    assert attrs.config["ssl"] == options[:ssl]
  end

  defp enabled_config(dir, env) do
    observability_config(dir, env)[:enabled]
  end

  defp observability_config(dir, env) do
    # Evaluate runtime configuration without applying it or starting telemetry.
    # An isolated directory prevents loading developer credentials from .env.
    File.cd!(dir, fn ->
      @runtime_path
      |> Config.Reader.read!(env: env, target: :host)
      |> get_in([:trifle, Trifle.Observability])
    end)
  end

  defp restore_application_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_application_env(app, key, value), do: Application.put_env(app, key, value)
end
