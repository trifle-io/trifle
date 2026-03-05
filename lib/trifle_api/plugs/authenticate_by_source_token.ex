defmodule TrifleApi.Plugs.AuthenticateBySourceToken do
  use Phoenix.Controller,
    formats: [:json],
    layouts: []

  import Plug.Conn
  alias Trifle.Organizations
  alias Trifle.Stats.Source

  def init(params), do: params

  def call(conn, params \\ %{mode: :any}) do
    with {:ok, auth} <- find_source_from_header(conn, params.mode) do
      conn
      |> assign(:current_api_token, auth.token)
      |> assign(:current_api_user, auth.user)
      |> assign(:current_source, auth.source)
      |> assign(:current_project, auth.project)
      |> assign(:current_database, auth.database)
    else
      {:error, :missing_source_id} ->
        conn
        |> assign(:current_project, nil)
        |> put_resp_content_type("application/json")
        |> put_status(:bad_request)
        |> json(%{errors: %{detail: "Missing X-Trifle-Source-Id header"}})
        |> halt()

      {:error, :invalid_source_id} ->
        conn
        |> assign(:current_project, nil)
        |> put_resp_content_type("application/json")
        |> put_status(:bad_request)
        |> json(%{errors: %{detail: "Invalid X-Trifle-Source-Id header"}})
        |> halt()

      {:error, :invalid_permissions} ->
        conn
        |> assign(:current_project, nil)
        |> put_resp_content_type("application/json")
        |> put_status(:forbidden)
        |> put_view(TrifleApi.ErrorJSON)
        |> render("403.json", %{})
        |> halt()

      _error ->
        conn
        |> assign(:current_project, nil)
        |> put_resp_content_type("application/json")
        |> put_status(:unauthorized)
        |> put_view(TrifleApi.ErrorJSON)
        |> render("401.json", %{})
        |> halt()
    end
  end

  def find_source_from_header(conn, mode) do
    with token when is_binary(token) <- extract_bearer_token(conn),
         {:ok, source_id} <- extract_source_id(conn),
         {:ok, %{token: token_record, user: user}} <- Organizations.get_api_token_auth(token),
         organization_id when is_binary(organization_id) <- token_record.organization_id,
         {:ok, source_type, record} <- Organizations.get_source_for_org(organization_id, source_id),
         :ok <- Organizations.ensure_token_permission(token_record, source_type, source_id, mode) do
      _ = Organizations.touch_organization_api_token(token, %{last_used_from: request_source(conn)})
      {:ok, build_auth(source_type, record, token_record, user)}
    else
      nil ->
        {:error, :not_found}

      {:error, :missing_source_id} ->
        {:error, :missing_source_id}

      {:error, :bad_request} ->
        {:error, :invalid_source_id}

      {:error, :invalid_source} ->
        {:error, :invalid_source_id}

      {:error, :invalid_permissions} ->
        {:error, :invalid_permissions}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp extract_bearer_token(conn) do
    case List.first(Plug.Conn.get_req_header(conn, "authorization")) do
      "Bearer " <> token -> token
      _ -> nil
    end
  end

  defp extract_source_id(conn) do
    case List.first(Plug.Conn.get_req_header(conn, "x-trifle-source-id")) do
      source_id when is_binary(source_id) and source_id != "" -> {:ok, source_id}
      _ -> {:error, :missing_source_id}
    end
  end

  defp request_source(conn) do
    conn
    |> Plug.Conn.get_req_header("x-trifle-client-host")
    |> List.first()
    |> case do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        conn
        |> Plug.Conn.get_req_header("user-agent")
        |> List.first()
    end
  end

  defp build_auth(:project, project, token_record, user) do
    %{
      source: Source.from_project(project),
      project: project,
      database: nil,
      user: user,
      token: token_record
    }
  end

  defp build_auth(:database, database, token_record, user) do
    %{
      source: Source.from_database(database),
      project: nil,
      database: database,
      user: user,
      token: token_record
    }
  end
end
