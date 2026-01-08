# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :trifle,
  ecto_repos: [Trifle.Repo]

config :trifle, :deployment_mode, :saas

config :trifle, :projects_enabled, true

# Configures the endpoint
config :trifle, TrifleWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: TrifleApp.ErrorHTML, json: TrifleApp.ErrorJSON],
    layout: false
  ],
  pubsub_server: Trifle.PubSub,
  live_view: [signing_salt: "c5enJmNY"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :trifle, Trifle.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.7",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Configure Honeybadger
config :honeybadger,
  environment_name: config_env(),
  # Enable logging and performance insights
  insights_enabled: true

# Configure New Relic
config :new_relic_agent,
  app_name: "Trifle",
  # License key is set via NEW_RELIC_LICENSE_KEY environment variable
  # Distributed tracing for better observability
  distributed_tracing_enabled: true

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :trifle, Trifle.Chat.Agent, history_limit: 40
config :trifle, Trifle.Chat.OpenAIClient, model: "gpt-5"

config :trifle, :slack,
  client_id: nil,
  client_secret: nil,
  signing_secret: nil,
  redirect_uri: nil,
  scopes: ~w(chat:write chat:write.public channels:read groups:read incoming-webhook)

config :trifle, :discord,
  client_id: nil,
  client_secret: nil,
  bot_token: nil,
  redirect_uri: nil,
  scopes: ~w(bot applications.commands identify guilds),
  permissions: 52_224

config :trifle, :google_oauth,
  client_id: nil,
  client_secret: nil,
  redirect_uri: nil

config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [default_scope: "openid email profile", prompt: "select_account", access_type: "offline"]}
  ]

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: nil,
  client_secret: nil

config :trifle, :oban_web_enabled, false

config :trifle, Oban,
  repo: Trifle.Repo,
  queues: [
    default: 10,
    monitors: 5,
    reports: 5,
    alerts: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron, crontab: [{"* * * * *", Trifle.Monitors.Jobs.DispatchRunner}]}
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
