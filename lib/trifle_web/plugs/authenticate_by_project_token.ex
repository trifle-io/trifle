defmodule TrifleWeb.Plugs.AuthenticateByProjectToken do
  use TrifleWeb, :controller
  import Plug.Conn
  alias Trifle.Organizations

  def init(params), do: params

  def call(conn, params \\ %{mode: :none}) do
    with {:ok, project} <- find_project_from_header(conn, params.mode) do
      conn
      |> assign(:current_project, project)
    else
      {:error, :invalid_permissions} ->
        conn
        |> assign(:current_project, nil)
        |> put_resp_content_type("application/json")
        |> put_status(:forbidden)
        |> put_view(TrifleWeb.Api.ErrorJSON)
        |> render("403.json", %{})
        |> halt()

      _error ->
        conn
        |> assign(:current_project, nil)
        |> put_resp_content_type("application/json")
        |> put_status(:unauthorized)
        |> put_view(TrifleWeb.Api.ErrorJSON)
        |> render("401.json", %{})
        |> halt()
    end
  end

  def find_project_from_header(conn, mode) do
    with token when not is_nil(token) <- extract_bearer_token(conn),
         {:ok, project, token} <- Trifle.Organizations.get_project_by_token(token),
         {:ok, permission} <- valid_mode?(token, mode) do
      {:ok, project}
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
    cond do
      token.read && mode == :read ->
        {:ok, :read}

      token.write && mode == :write ->
        {:ok, :write}

      true ->
        # true is else
        {:error, :invalid_permissions}
    end
  end
end
