defmodule TrifleApi.ConnectorsController do
  use TrifleApi, :controller

  alias Ecto.Changeset
  alias Trifle.Organizations
  alias Trifle.Organizations.ConnectorJob
  alias Trifle.Organizations.OrganizationConnector

  plug TrifleApi.Plugs.AuthenticateConnector

  def heartbeat(
        %{assigns: %{current_connector: %OrganizationConnector{} = connector}} = conn,
        params
      ) do
    with :ok <- ensure_connector_id(connector, params["connector_id"]),
         attrs <- heartbeat_attrs(params),
         {:ok, updated_connector} <- Organizations.record_connector_heartbeat(connector, attrs) do
      json(conn, %{data: %{connector: connector_json(updated_connector)}})
    else
      :connector_mismatch ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "connector_id_mismatch"}})

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def jobs(%{assigns: %{current_connector: %OrganizationConnector{} = connector}} = conn, params) do
    with :ok <- ensure_connector_id(connector, params["connector_id"]) do
      _ = Organizations.touch_connector_poll(connector)
      jobs = Organizations.list_pending_connector_jobs(connector)

      json(conn, %{data: %{jobs: Enum.map(jobs, &job_json/1)}})
    else
      :connector_mismatch ->
        conn
        |> put_status(:forbidden)
        |> json(%{errors: %{detail: "connector_id_mismatch"}})
    end
  end

  def complete_job(
        %{assigns: %{current_connector: %OrganizationConnector{} = connector}} = conn,
        params
      ) do
    case Organizations.complete_connector_job(connector, params["id"], completion_attrs(params)) do
      {:ok, _job} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: %{detail: "not_found"}})

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  defp ensure_connector_id(%OrganizationConnector{id: id}, value)
       when value in [nil, ""] or value == id,
       do: :ok

  defp ensure_connector_id(%OrganizationConnector{}, _value), do: :connector_mismatch

  defp heartbeat_attrs(params) do
    %{}
    |> put_if_present(:name, params["name"])
    |> put_if_present(:version, params["version"])
    |> put_if_present(:commit, params["commit"])
    |> put_if_present(:build_date, params["build_date"])
    |> put_if_present(:hostname, params["hostname"])
    |> put_if_list(:capabilities, params["capabilities"])
    |> put_if_map(:metadata, params["metadata"])
  end

  defp completion_attrs(params) do
    %{}
    |> put_if_present(:status, params["status"])
    |> put_if_map(:result, params["result"])
    |> put_if_present(:error, params["error"])
    |> put_if_list(:logs, params["logs"])
  end

  defp put_if_present(acc, _key, value) when value in [nil, ""], do: acc

  defp put_if_present(acc, key, value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: acc, else: Map.put(acc, key, value)
  end

  defp put_if_present(acc, key, value), do: Map.put(acc, key, value)

  defp put_if_list(acc, key, value) when is_list(value), do: Map.put(acc, key, value)
  defp put_if_list(acc, _key, _value), do: acc

  defp put_if_map(acc, key, value) when is_map(value), do: Map.put(acc, key, value)
  defp put_if_map(acc, _key, _value), do: acc

  defp connector_json(%OrganizationConnector{} = connector) do
    %{
      id: connector.id,
      name: connector.name,
      status: connector.status,
      last_heartbeat_at: connector.last_heartbeat_at,
      last_poll_at: connector.last_poll_at,
      last_seen_at: connector.last_seen_at,
      version: connector.version,
      hostname: connector.hostname,
      capabilities: connector.capabilities || []
    }
  end

  defp job_json(%ConnectorJob{} = job) do
    %{
      id: job.id,
      type: job.type,
      payload: job.payload || %{}
    }
  end

  defp changeset_errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
