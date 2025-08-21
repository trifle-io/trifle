defmodule Trifle.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      TrifleWeb.Telemetry,
      # Start the Ecto repository (main application PostgreSQL)
      Trifle.Repo,
      # Start dynamic database connection pool supervisors
      Trifle.DatabasePools.PostgresPoolSupervisor,
      Trifle.DatabasePools.MongoPoolSupervisor,
      Trifle.DatabasePools.RedisPoolSupervisor,
      Trifle.DatabasePools.SqlitePoolSupervisor,
      Trifle.DatabasePools.MySQLPoolSupervisor,
      # Start the PubSub system
      {Phoenix.PubSub, name: Trifle.PubSub},
      # Start Finch
      {Finch, name: Trifle.Finch},
      # Start the Endpoint (http/https)
      TrifleWeb.Endpoint
      # Start a worker by calling: Trifle.Worker.start_link(arg)
      # {Trifle.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Trifle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TrifleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
