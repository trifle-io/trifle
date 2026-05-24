defmodule Trifle.Networking.SSHTunnelSupervisor do
  @moduledoc """
  Dynamic supervisor for SSH tunnels used by database connections.
  """

  use DynamicSupervisor

  alias Trifle.Networking.SSHTunnel

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_tunnel(%{id: database_id} = database) when is_binary(database_id) do
    expected_version = pool_version(database)
    tunnel_name = SSHTunnel.name(database_id)

    case Process.whereis(tunnel_name) do
      nil ->
        start_new_tunnel(database, expected_version)

      pid ->
        case Trifle.DatabasePools.VersionRegistry.get(:ssh_tunnel, database_id) do
          {:ok, ^expected_version} ->
            SSHTunnel.endpoint(pid)

          _ ->
            _ = stop_tunnel(database_id)
            start_new_tunnel(database, expected_version)
        end
    end
  end

  def stop_tunnel(database_id) when is_binary(database_id) do
    tunnel_name = SSHTunnel.name(database_id)

    result =
      case Process.whereis(tunnel_name) do
        nil -> :ok
        pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      end

    _ = Trifle.DatabasePools.VersionRegistry.delete(:ssh_tunnel, database_id)
    result
  end

  defp start_new_tunnel(database, expected_version) do
    case DynamicSupervisor.start_child(__MODULE__, {SSHTunnel, database}) do
      {:ok, pid} ->
        _ = Trifle.DatabasePools.VersionRegistry.put(:ssh_tunnel, database.id, expected_version)
        SSHTunnel.endpoint(pid)

      {:error, {:already_started, pid}} ->
        _ = Trifle.DatabasePools.VersionRegistry.put(:ssh_tunnel, database.id, expected_version)
        SSHTunnel.endpoint(pid)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pool_version(database) do
    case Map.get(database, :pool_version) do
      version when is_integer(version) and version > 0 -> version
      _ -> 1
    end
  end
end
