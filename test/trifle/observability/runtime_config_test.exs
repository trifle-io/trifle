defmodule Trifle.Observability.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime_path Path.expand("../../../config/runtime.exs", __DIR__)
  @moduletag :tmp_dir

  setup do
    env_keys = ~w(DOTENV_PATH TRIFLE_OBSERVABILITY_ENABLED DATABASE_URL SECRET_KEY_BASE
                  TRIFLE_DB_ENCRYPTION_KEY MAILER_ADAPTER)
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

  defp enabled_config(dir, env) do
    # Evaluate runtime configuration without applying it or starting telemetry.
    # An isolated directory prevents loading developer credentials from .env.
    File.cd!(dir, fn ->
      @runtime_path
      |> Config.Reader.read!(env: env, target: :host)
      |> get_in([:trifle, Trifle.Observability, :enabled])
    end)
  end
end
