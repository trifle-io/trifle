defmodule Trifle.Organizations.NetworkConnections do
  @moduledoc "Organization-owned Tailscale enrollment and connection lifecycle."
  import Ecto.Query
  alias Ecto.Changeset
  alias Trifle.Repo
  alias Trifle.Organizations.{Database, NetworkConnection, Organization}

  def client, do: Application.get_env(:trifle, :network_gateway_client, Trifle.Networking.Gateway)
  def list(%Organization{id: id}), do: list(id)

  def list(org_id),
    do:
      Repo.all(
        from n in NetworkConnection,
          where: n.organization_id == ^org_id,
          order_by: n.name,
          select:
            struct(n, [
              :id,
              :organization_id,
              :name,
              :provider,
              :enabled,
              :generation,
              :status,
              :hostname,
              :addresses,
              :last_error,
              :checked_at
            ])
      )

  def get(org_id, id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         do: Repo.get_by(NetworkConnection, id: id, organization_id: org_id),
         else: (_ -> nil)
  end

  def create(%Organization{id: org_id}, attrs) do
    %NetworkConnection{organization_id: org_id}
    |> NetworkConnection.changeset(attrs)
    |> Changeset.validate_required([:auth_key])
    |> Repo.insert()
  end

  def refresh(%NetworkConnection{} = connection) do
    # Serialize lifecycle changes across App replicas. Never send a stale
    # generation/credential to the gateway after another replica disconnects.
    transact(connection, fn current ->
      with {:ok, _} <- client().configure(current),
           {:ok, status} <- client().status(current) do
        state = status["state"]

        attrs = %{
          status: status_name(state),
          hostname: status["hostname"],
          addresses: status["ips"] || [],
          checked_at: now(),
          last_error: nil
        }

        attrs =
          if status["enrolled"] == true and state == "Running",
            do: Map.put(attrs, :auth_key, nil),
            else: attrs

        current |> Changeset.change(attrs) |> Repo.update()
      else
        {:error, reason} ->
          current
          |> Changeset.change(%{
            status: "error",
            checked_at: now(),
            last_error: error_message(reason)
          })
          |> Repo.update()
      end
    end)
  end

  def reauthorize(connection, auth_key) do
    transact(connection, fn current ->
      current
      |> NetworkConnection.changeset(%{auth_key: auth_key})
      |> Changeset.validate_required([:auth_key])
      |> Changeset.change(%{
        generation: current.generation + 1,
        enabled: true,
        status: "pending",
        last_error: nil
      })
      |> Repo.update()
    end)
  end

  def disconnect(connection) do
    transact(connection, fn current ->
      disabled = %{current | enabled: false, generation: current.generation + 1, auth_key: nil}

      with {:ok, _} <- client().configure(disabled) do
        current
        |> Changeset.change(%{
          enabled: false,
          generation: disabled.generation,
          auth_key: nil,
          status: "disconnected",
          last_error: nil,
          addresses: []
        })
        |> Repo.update()
      end
    end)
  end

  def delete(connection) do
    transact(connection, fn current ->
      if Repo.exists?(
           from d in Database,
             where:
               d.network_connection_id == ^current.id or
                 d.trace_network_connection_id == ^current.id
         ) do
        {:error, :connection_in_use}
      else
        disabled = %{current | enabled: false, generation: current.generation + 1, auth_key: nil}
        with {:ok, _} <- client().configure(disabled), do: Repo.delete(current)
      end
    end)
  end

  def available(org_id, id) do
    case get(org_id, id) do
      %NetworkConnection{enabled: true} = connection -> {:ok, connection}
      _ -> {:error, :network_connection_unavailable}
    end
  end

  def error_message(:gateway_not_configured),
    do: "The network gateway is not configured for this deployment."

  def error_message(:connection_in_use),
    do: "Reassign database and trace storage sources before deleting this connection."

  def error_message({:gateway_status, 422}), do: "A fresh Tailscale auth key is required."

  def error_message({:gateway_status, 409}),
    do: "Connection configuration changed. Refresh and try again."

  def error_message(_), do: "The network gateway is unavailable. Check its status and try again."

  defp transact(connection, fun) do
    result =
      Repo.transaction(fn ->
        current =
          Repo.one!(
            from n in NetworkConnection,
              where: n.id == ^connection.id and n.organization_id == ^connection.organization_id,
              lock: "FOR UPDATE"
          )

        case fun.(current) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, updated} ->
        if updated.generation != connection.generation or not updated.enabled do
          Phoenix.PubSub.broadcast(Trifle.PubSub, "network:#{connection.id}", :network_changed)
        end

      _ ->
        :ok
    end

    result
  end

  defp status_name("Running"), do: "online"
  defp status_name("NeedsMachineAuth"), do: "approval_required"
  defp status_name("NeedsLogin"), do: "needs_authorization"
  defp status_name("Stopped"), do: "disconnected"
  defp status_name(_), do: "pending"
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
