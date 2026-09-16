defmodule Trifle.Observability.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_path Path.expand("../../../config/runtime.exs", __DIR__)
  @moduletag :tmp_dir

  setup do
    env_keys = ~w(DOTENV_PATH TRIFLE_OBSERVABILITY_ENABLED DATABASE_URL SECRET_KEY_BASE
                  TRIFLE_DB_ENCRYPTION_KEY MAILER_ADAPTER TRIFLE_TRACES_GZIP
                  TRIFLE_TRACES_S3_SECRET_ACCESS_KEY)
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
end
