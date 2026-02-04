import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :trifle, Trifle.Repo,
  username: "postgres",
  password: "password",
  hostname: "postgres",
  database: "trifle_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :trifle, TrifleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "wAW2Keg5xUQKnlgvnHhLyF9SrHJru2sDZIIQ1PoI6z7vtyVGXhsZC2i/e76ZJwa5",
  server: false

# In test we don't send emails.
config :trifle, Trifle.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Encryption config for tests/migrations.
default_db_encryption_key = String.duplicate("0", 32)

db_encryption_key =
  case System.get_env("TRIFLE_DB_ENCRYPTION_KEY") do
    nil ->
      default_db_encryption_key

    "" ->
      default_db_encryption_key

    value ->
      case Base.decode64(value) do
        {:ok, key} when byte_size(key) == 32 -> key
        _ -> default_db_encryption_key
      end
  end

config :trifle, Trifle.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: db_encryption_key}
  ]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :trifle, Trifle.Chat.OpenAIClient, api_key: nil, model: "gpt-5"

config :trifle, Oban,
  testing: :inline,
  queues: false,
  plugins: false

config :trifle, :oban_web_enabled, false
