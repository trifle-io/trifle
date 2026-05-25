defmodule TrifleApi.Plugs.AuthenticateConnector do
  use Phoenix.Controller,
    formats: [:json],
    layouts: []

  import Plug.Conn

  alias Trifle.Organizations

  def init(params), do: params

  def call(conn, _params) do
    with token when is_binary(token) <- extract_bearer_token(conn),
         {:ok, %{connector: connector, organization: organization}} <-
           Organizations.get_connector_auth(token) do
      conn
      |> assign(:current_connector, connector)
      |> assign(:current_connector_organization, organization)
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
      "Bearer " <> token -> String.trim(token)
      _ -> nil
    end
  end
end
