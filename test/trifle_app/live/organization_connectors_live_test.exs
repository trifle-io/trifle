defmodule TrifleApp.OrganizationConnectorsLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  setup %{conn: conn} do
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})

    {:ok, conn: log_in_user(conn, user), organization: organization}
  end

  test "renders connector onboarding and creates a private connector", %{
    conn: conn,
    organization: organization
  } do
    {:ok, lv, html} = live(conn, ~p"/organization/connectors")

    assert html =~ "Private Connectors"
    assert html =~ "No private connectors yet."

    html =
      lv
      |> element("button", "New connector")
      |> render_click()

    assert html =~ "Create connector"

    html =
      lv
      |> element("form[phx-submit=\"create_connector\"]")
      |> render_submit(%{"connector" => %{"name" => "Production VPC"}})

    assert html =~ "Private connector created"
    assert html =~ "trf_connector_"
    assert html =~ "docker run -d --name trifle-connector"
    assert html =~ "trifle/connector:latest"
    assert html =~ "Production VPC"

    assert [%{name: "Production VPC"}] = Organizations.list_connectors_for_org(organization)
  end
end
