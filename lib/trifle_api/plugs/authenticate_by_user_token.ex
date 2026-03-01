defmodule TrifleApi.Plugs.AuthenticateByUserToken do
  use Phoenix.Controller,
    formats: [:json],
    layouts: []

  import Plug.Conn

  alias Trifle.Accounts

  def init(params), do: params

  def call(conn, _params) do
    with token when is_binary(token) <- extract_bearer_token(conn),
         user when not is_nil(user) <- Accounts.get_user_by_api_token(token) do
      _ = Accounts.touch_user_api_token(token, %{last_used_from: request_source(conn)})

      conn
      |> assign(:current_api_user, user)
      |> assign(:current_user_api_token, token)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> put_status(:unauthorized)
        |> put_view(TrifleApi.ErrorJSON)
        |> render("401.json", %{})
        |> halt()
    end
  end

  defp extract_bearer_token(conn) do
    case List.first(Plug.Conn.get_req_header(conn, "authorization")) do
      "Bearer " <> token -> token
      _ -> nil
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
end
