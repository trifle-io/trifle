defmodule Trifle.MixProject do
  use Mix.Project

  def project do
    [
      app: :trifle,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader],
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Trifle.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 3.0"},
      {:phoenix, "~> 1.8.0"},
      {:phoenix_ecto, "~> 4.6"},
      {:ecto_sql, "~> 3.12"},
      {:ecto_psql_extras, "~> 0.8"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0.0"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.5"},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.3"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:slugy, "~> 4.1.1"},
      {:tzdata, "~> 1.1.1"},
      {:timex, "~>3.7.11"},
      # {:trifle_stats, path: "../trifle_stats"},
      # {:trifle_stats, "~>1.0.0"},
      {:trifle_stats, git: "https://github.com/trifle-io/trifle_stats.git", branch: "main"},
      {:mongodb_driver, "~> 1.2.0"},
      {:myxql, "~> 0.7.0"},
      {:redix, "~> 1.3.0"},
      {:exqlite, "~> 0.20"},
      {:honeybadger, "~> 0.22"},
      {:mint_web_socket, "~> 1.0"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": [
        "tailwind.install --if-missing",
        "esbuild.install --if-missing",
        "cmd cd assets && npm install"
      ],
      "assets.build": [
        "tailwind default",
        "esbuild default",
        # Ensure vendor assets (like gridstack CSS) are available under priv/static for CSS @import
        "cmd mkdir -p priv/static/vendor",
        "cmd cp -f assets/node_modules/gridstack/dist/gridstack.min.css priv/static/vendor/gridstack.min.css"
      ],
      "assets.deploy": [
        "cmd cd assets && npm install",
        "tailwind default --minify",
        "esbuild default --minify",
        "cmd mkdir -p priv/static/vendor",
        "cmd cp -f assets/node_modules/gridstack/dist/gridstack.min.css priv/static/vendor/gridstack.min.css",
        "phx.digest"
      ]
    ]
  end
end
