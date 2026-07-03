defmodule Trifle.Organizations.Connectors do
  @moduledoc """
  Organization connectors: registration, token auth, heartbeats, and the
  connector job queue (enqueue / poll / complete).
  """

  import Ecto.Query, warn: false

  alias Trifle.Organizations.Attrs
  alias Trifle.Organizations.ConnectorJob
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.OrganizationConnector
  alias Trifle.Repo

  def list_connectors_for_org(%Organization{} = organization) do
    list_connectors_for_org(organization.id)
  end

  def list_connectors_for_org(organization_id) when is_binary(organization_id) do
    from(a in OrganizationConnector,
      where: a.organization_id == ^organization_id,
      order_by: [desc: a.last_seen_at, desc: a.inserted_at]
    )
    |> Repo.all()
  end

  def get_connector_for_org!(%Organization{} = organization, id) when is_binary(id) do
    get_connector_for_org!(organization.id, id)
  end

  def get_connector_for_org!(organization_id, id)
      when is_binary(organization_id) and is_binary(id) do
    Repo.get_by!(OrganizationConnector, id: id, organization_id: organization_id)
  end

  def get_connector_for_org(organization_id, id)
      when is_binary(organization_id) and is_binary(id) do
    Repo.get_by(OrganizationConnector, id: id, organization_id: organization_id)
  end

  def create_connector_for_org(%Organization{} = organization, attrs \\ %{}) do
    token_value = OrganizationConnector.build_token()

    attrs =
      attrs
      |> Map.new()
      |> Attrs.assign_org_id(organization)
      |> Attrs.atomize_keys()
      |> Map.put(:token_hash, OrganizationConnector.hash_token(token_value))
      |> Map.put(:token_last5, OrganizationConnector.token_last5(token_value))

    case %OrganizationConnector{}
         |> OrganizationConnector.changeset(attrs)
         |> Repo.insert() do
      {:ok, connector} -> {:ok, connector, token_value}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def change_connector(%OrganizationConnector{} = connector, attrs \\ %{}) do
    OrganizationConnector.changeset(connector, attrs)
  end

  def delete_connector(%OrganizationConnector{} = connector) do
    Repo.transaction(fn ->
      from(d in Database, where: d.organization_connector_id == ^connector.id)
      |> Repo.update_all(
        set: [connection_method: "direct", organization_connector_id: nil],
        inc: [pool_version: 1]
      )

      case Repo.delete(connector) do
        {:ok, deleted} -> deleted
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def get_connector_auth(token) when is_binary(token) do
    token
    |> OrganizationConnector.valid_query()
    |> Repo.one()
    |> Repo.preload(:organization)
    |> case do
      %OrganizationConnector{} = connector ->
        {:ok, %{connector: connector, organization: connector.organization}}

      _ ->
        {:error, :not_found}
    end
  end

  def get_connector_auth(_), do: {:error, :not_found}

  def record_connector_heartbeat(%OrganizationConnector{} = connector, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs =
      attrs
      |> Map.new()
      |> Attrs.atomize_keys()
      |> Map.take([
        :name,
        :version,
        :commit,
        :build_date,
        :hostname,
        :capabilities,
        :metadata
      ])
      |> Map.merge(%{
        status: "online",
        last_heartbeat_at: now,
        last_seen_at: now,
        last_error: nil
      })

    connector
    |> OrganizationConnector.changeset(attrs)
    |> Repo.update()
  end

  def touch_connector_poll(%OrganizationConnector{} = connector) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    connector
    |> OrganizationConnector.changeset(%{
      status: "online",
      last_poll_at: now,
      last_seen_at: now
    })
    |> Repo.update()
  end

  def enqueue_connector_job(%OrganizationConnector{} = connector, type, payload \\ %{}) do
    %ConnectorJob{}
    |> ConnectorJob.changeset(%{
      organization_connector_id: connector.id,
      type: to_string(type),
      payload: payload || %{}
    })
    |> Repo.insert()
  end

  def list_pending_connector_jobs(%OrganizationConnector{} = connector, limit \\ 10) do
    limit = max(1, min(limit, 50))

    Repo.transaction(fn ->
      jobs =
        from(j in ConnectorJob,
          where: j.organization_connector_id == ^connector.id and j.status == "pending",
          order_by: [asc: j.inserted_at],
          limit: ^limit,
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.all()

      ids = Enum.map(jobs, & &1.id)

      if ids != [] do
        from(j in ConnectorJob, where: j.id in ^ids)
        |> Repo.update_all(set: [status: "running"])
      end

      Enum.map(jobs, fn job -> %{job | status: "running"} end)
    end)
    |> case do
      {:ok, jobs} -> jobs
      {:error, _reason} -> []
    end
  end

  def complete_connector_job(%OrganizationConnector{} = connector, job_id, attrs)
      when is_binary(job_id) and is_map(attrs) do
    case Repo.get_by(ConnectorJob, id: job_id, organization_connector_id: connector.id) do
      %ConnectorJob{} = job ->
        attrs =
          attrs
          |> Map.new()
          |> Attrs.atomize_keys()
          |> normalize_connector_job_completion_attrs()
          |> maybe_scrub_connector_job_payload(job)

        job
        |> ConnectorJob.changeset(attrs)
        |> Repo.update()

      nil ->
        {:error, :not_found}
    end
  end

  def complete_connector_job(_connector, _job_id, _attrs), do: {:error, :not_found}

  defp normalize_connector_job_completion_attrs(attrs) do
    status =
      case Map.get(attrs, :status) do
        value when value in ["ok", "error"] -> value
        "completed" -> "ok"
        value -> value
      end

    attrs
    |> Map.take([:status, :result, :error, :logs])
    |> Map.put(:status, status)
    |> Map.put(:completed_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  defp maybe_scrub_connector_job_payload(attrs, %ConnectorJob{type: "stats_values"} = job) do
    Map.put(attrs, :payload, scrub_connector_job_payload(job.payload))
  end

  defp maybe_scrub_connector_job_payload(attrs, _job), do: attrs

  defp scrub_connector_job_payload(value) when is_map(value) do
    Map.new(value, fn
      {key, _value} when key in ["password", :password] -> {key, "[redacted]"}
      {key, nested} -> {key, scrub_connector_job_payload(nested)}
    end)
  end

  defp scrub_connector_job_payload(values) when is_list(values) do
    Enum.map(values, &scrub_connector_job_payload/1)
  end

  defp scrub_connector_job_payload(value), do: value
end
