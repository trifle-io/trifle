defmodule TrifleApi.Plugs.AuthenticateByOrganizationToken do
  use Phoenix.Controller,
    formats: [:json],
    layouts: []

  import Plug.Conn

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationMembership

  def init(params), do: params

  def call(conn, _params) do
    with token when is_binary(token) <- extract_bearer_token(conn),
         {:ok, %{token: token_record, user: user, organization: organization}} <-
           Organizations.get_api_token_auth(token),
         {:ok, token_record, organization} <-
           maybe_bind_token_to_membership(token_record, user, organization) do
      _ = Organizations.touch_organization_api_token(token, %{last_used_from: request_source(conn)})

      conn
      |> assign(:current_api_token, token_record)
      |> assign(:current_api_user, user)
      |> assign(:current_api_organization, organization)
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

  defp maybe_bind_token_to_membership(token_record, _user, organization)
       when not is_nil(token_record.organization_id) do
    {:ok, token_record, organization}
  end

  defp maybe_bind_token_to_membership(token_record, user, _organization) do
    case Organizations.get_membership_for_user(user) do
      %OrganizationMembership{} = membership ->
        case Organizations.update_organization_api_token(token_record, %{
               organization_id: membership.organization_id
             }) do
          {:ok, updated} -> {:ok, updated, membership.organization}
          {:error, _} -> {:ok, token_record, membership.organization}
        end

      _ ->
        {:ok, token_record, nil}
    end
  end
end
