defmodule Trifle.Networking.RefreshConnections do
  @moduledoc "Refreshes enrollment and health independently of browser sessions. No query polling."
  use Oban.Worker,
    queue: :default,
    max_attempts: 2,
    unique: [period: 55, fields: [:worker, :args]]

  import Ecto.Query
  alias Trifle.Organizations.{NetworkConnection, NetworkConnections}
  alias Trifle.Repo
  alias Trifle.Traces

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"organization_id" => org_id, "id" => id}}) do
    Traces.trace("Refresh network connection", head: true)
    Traces.tag("organization:#{org_id}")
    Traces.tag("network-connection:#{id}")
    Traces.trace("Load network connection")

    case NetworkConnections.get(org_id, id) do
      %NetworkConnection{enabled: true} = connection ->
        Traces.trace("Network connection is enabled")

        case NetworkConnections.refresh(connection) do
          {:ok, updated} ->
            trace_status(updated)
            :ok

          {:error, _} ->
            Traces.trace("Network connection refresh could not be saved", state: :error)
            Traces.fail()
            {:error, :gateway_unavailable}
        end

      %NetworkConnection{} ->
        Traces.trace("Network connection is disabled; skipping refresh")
        :ok

      nil ->
        Traces.trace("Network connection no longer exists; skipping refresh", state: :warning)
        Traces.warn()
        :ok
    end
  end

  def perform(%Oban.Job{}) do
    Traces.trace("Dispatch network connection refreshes", head: true)
    Traces.trace("Load enabled network connections")

    # Only identifiers enter Oban arguments, telemetry, and trace logs.
    connections =
      Repo.all(
        from n in NetworkConnection,
          where: n.enabled,
          select: %{organization_id: n.organization_id, id: n.id}
      )

    total = length(connections)
    Traces.trace("Enabled network connections: #{total}")

    {enqueued, skipped} =
      connections
      |> Enum.with_index(1)
      |> Enum.reduce({0, 0}, fn {args, position}, {enqueued, skipped} ->
        Traces.trace("Network connection #{position} of #{total}", head: true)
        Traces.tag("organization:#{args.organization_id}")
        Traces.tag("network-connection:#{args.id}")
        Traces.trace("Enqueue network connection refresh")

        case args |> new() |> Oban.insert!() do
          %Oban.Job{conflict?: true} ->
            Traces.trace("Refresh job already queued; skipping duplicate")
            {enqueued, skipped + 1}

          %Oban.Job{id: job_id} ->
            Traces.tag("refresh-job:#{job_id}")
            Traces.trace("Refresh job enqueued")
            {enqueued + 1, skipped}
        end
      end)

    Traces.trace("Refresh dispatch summary", head: true)
    Traces.trace("Enqueued: #{enqueued}; already queued: #{skipped}")

    :ok
  end

  defp trace_status(connection) do
    state =
      case connection.status do
        "online" -> :success
        "error" -> :error
        _ -> :warning
      end

    Traces.trace("Network connection refresh saved; status: #{connection.status}", state: state)

    case state do
      :error -> Traces.fail()
      :warning -> Traces.warn()
      :success -> :ok
    end
  end
end
