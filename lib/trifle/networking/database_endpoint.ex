defmodule Trifle.Networking.DatabaseEndpoint do
  @moduledoc """
  Resolves the host and port that database drivers should connect to.
  """

  alias Trifle.Networking.SSHTunnelSupervisor
  alias Trifle.Organizations.Database

  def resolve(%Database{connection_method: "agent"}) do
    {:error, :agent_connection_not_supported}
  end

  def resolve(%Database{connection_method: "connector"}) do
    {:error, :connector_connection_not_implemented}
  end

  def resolve(%Database{connection_method: "direct", driver: "sqlite"}) do
    {:ok, %{host: nil, port: nil, via: :local}}
  end

  def resolve(%Database{connection_method: "ssh_tunnel"} = database) do
    with {:ok, endpoint} <- SSHTunnelSupervisor.start_tunnel(database) do
      {:ok,
       endpoint
       |> Map.put(:via, :ssh_tunnel)
       |> Map.put(:source_host, database.host)
       |> Map.put(:source_port, database.port || Database.default_port(database.driver))}
    end
  end

  def resolve(%Database{connection_method: "direct"} = database) do
    {:ok,
     %{
       host: database.host,
       port: database.port || Database.default_port(database.driver),
       via: :direct
     }}
  end

  def resolve(%Database{}) do
    {:error, :unsupported_connection_method}
  end
end
