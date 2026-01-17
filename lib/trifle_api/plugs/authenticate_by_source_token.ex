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
      |> assign(:current_source, auth.source)
      |> assign(:current_project, auth.project)
      |> assign(:current_database, auth.database)
    else
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
    with token when not is_nil(token) <- extract_bearer_token(conn),
         {:ok, source_type, record, token_record} <- fetch_source_by_token(token),
         {:ok, _permission} <- valid_mode?(token_record, mode) do
      {:ok, build_auth(source_type, record, token_record)}
    else
      {:error, :invalid_permissions} ->
        {:error, :invalid_permissions}

      {:error, :not_found} ->
        {:error, :not_found}

      nil ->
        {:error, :not_found}
    end
  end

  defp extract_bearer_token(conn) do
    case List.first(Plug.Conn.get_req_header(conn, "authorization")) do
      "Bearer " <> token -> token
      _ -> nil
    end
  end

  def valid_mode?(token, mode) do
    read = Map.get(token, :read, false)
    write = Map.get(token, :write, false)

    cond do
      mode in [:any, :none, nil] ->
        {:ok, :any}

      read && mode == :read ->
        {:ok, :read}

      write && mode == :write ->
        {:ok, :write}

      true ->
        # true is else
        {:error, :invalid_permissions}
    end
  end

  defp fetch_source_by_token(token) do
    case Organizations.get_project_by_token(token) do
      {:ok, project, record} ->
        {:ok, :project, project, record}

      {:error, :not_found} ->
        case Organizations.get_database_by_token(token) do
          {:ok, database, record} -> {:ok, :database, database, record}
          {:error, :not_found} -> {:error, :not_found}
        end
    end
  end

  defp build_auth(:project, project, token_record) do
    %{
      source: Source.from_project(project),
      project: project,
      database: nil,
      token: token_record
    }
  end

  defp build_auth(:database, database, token_record) do
    %{
      source: Source.from_database(database),
      project: nil,
      database: database,
      token: token_record
    }
  end
end
