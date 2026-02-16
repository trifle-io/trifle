defmodule TrifleApp.DatabasesLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  setup %{conn: conn} do
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})

    {:ok, conn: log_in_user(conn, user), organization: organization}
  end

  test "new database form exposes MySQL driver option", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/dbs/new")

    assert html =~ "Driver"
    assert html =~ "MySQL"
  end

  test "mysql database is rendered as supported in databases list", %{
    conn: conn,
    organization: organization
  } do
    assert {:ok, database} =
             Organizations.create_database_for_org(
               organization,
               mysql_attrs(%{display_name: "Main MySQL"})
             )

    {:ok, _lv, html} = live(conn, ~p"/dbs")

    assert html =~ database.display_name
    assert html =~ "MySQL"
    refute html =~ "Unsupported"
  end

  test "database settings uses MySQL display name", %{conn: conn, organization: organization} do
    assert {:ok, database} = Organizations.create_database_for_org(organization, mysql_attrs())

    {:ok, _lv, html} = live(conn, ~p"/dbs/#{database.id}/settings")

    assert html =~ "MySQL database connection"
  end

  defp mysql_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        display_name: "Analytics MySQL",
        driver: "mysql",
        host: "127.0.0.1",
        port: 3306,
        database_name: "analytics",
        username: "trifle",
        password: "secret"
      },
      overrides
    )
  end
end
