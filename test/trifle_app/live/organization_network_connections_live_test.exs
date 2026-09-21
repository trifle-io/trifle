defmodule TrifleApp.OrganizationNetworkConnectionsLiveTest do
  use TrifleApp.ConnCase
  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  setup %{conn: conn} do
    Application.put_env(:trifle, :network_gateway_client, Trifle.NetworkGatewayStub)
    on_exit(fn -> Application.delete_env(:trifle, :network_gateway_client) end)
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    {:ok, conn: log_in_user(conn, user), organization: organization}
  end

  test "enrolls a named Tailscale connection without redisplaying its key", %{
    conn: conn,
    organization: org
  } do
    {:ok, view, html} = live(conn, ~p"/organization/connections")
    assert html =~ "No Tailscale connections yet."

    view
    |> form("#network-connection-form")
    |> render_submit(%{
      "connection" => %{name: "Production", auth_key: "tskey-auth-private-test"}
    })

    html = render_async(view)
    assert html =~ "Production"
    assert html =~ "Connected"
    assert html =~ "100.64.0.5"
    refute html =~ "tskey-auth-private-test"
    assert [%{auth_key: nil}] = Trifle.Organizations.NetworkConnections.list(org)
  end

  test "validates the credential type", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/organization/connections")

    html =
      view
      |> form("#network-connection-form")
      |> render_submit(%{"connection" => %{name: "Production", auth_key: "tskey-api-secret"}})

    assert html =~ "not an API access token"
    refute html =~ "tskey-api-secret"
  end

  test "a forged other-organization connection ID cannot be disconnected", %{conn: conn} do
    other =
      network_connection_fixture(%{
        organization: organization_fixture(%{name: "Another organization"})
      })

    {:ok, view, _} = live(conn, ~p"/organization/connections")
    render_click(view, "disconnect", %{"id" => other.id})
    assert Trifle.Repo.reload!(other).enabled
  end
end
