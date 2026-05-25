defmodule Trifle.Networking.DatabaseEndpoint do
  @moduledoc """
  Resolves the host and port that database drivers should connect to.
  """

  alias Trifle.Networking.SSHTunnelSupervisor
  alias Trifle.Organizations.Database

  def resolve(%Database{driver: "sqlite"} = database) do
    {:ok, %{host: database.host, port: database.port, via: :local}}
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

  def resolve(%Database{connection_method: "connector"}) do
    {:error, :connector_connection_not_implemented}
  end

  def resolve(%Database{} = database) do
    {:ok,
     %{
       host: database.host,
       port: database.port || Database.default_port(database.driver),
       via: :direct
     }}
  end
end
