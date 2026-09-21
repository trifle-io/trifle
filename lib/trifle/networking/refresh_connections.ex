defmodule Trifle.Networking.RefreshConnections do
  @moduledoc "Refreshes enrollment and health independently of browser sessions. No query polling."
  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [period: 55, fields: [:worker, :args]]

  import Ecto.Query
  alias Trifle.Organizations.{NetworkConnection, NetworkConnections}
  alias Trifle.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => org_id, "id" => id}}) do
    case NetworkConnections.get(org_id, id) do
      %NetworkConnection{enabled: true} = connection ->
        case NetworkConnections.refresh(connection) do
          {:ok, _} -> :ok
          {:error, _} -> {:error, :gateway_unavailable}
        end

      _ ->
        :ok
    end
  end

  def perform(%Oban.Job{}) do
    # Only identifiers enter Oban arguments, telemetry, and trace logs.
    Repo.all(
      from n in NetworkConnection,
        where: n.enabled,
        select: %{organization_id: n.organization_id, id: n.id}
    )
    |> Enum.each(fn args -> args |> new() |> Oban.insert!() end)

    :ok
  end
end
