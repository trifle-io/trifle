defmodule TrifleAdmin.DatabasesLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias TrifleAdmin.DatabasesLive.FormComponent

  setup %{conn: conn} do
    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})

    {:ok, conn: log_in_user(conn, user), organization: organization}
  end

  test "admin databases index shows MySQL label", %{conn: conn, organization: organization} do
    assert {:ok, _database} = Organizations.create_database_for_org(organization, mysql_attrs())

    {:ok, _lv, html} = live(conn, "/admin/databases")

    assert html =~ "MySQL"
  end

  test "admin database details modal uses MySQL display name", %{
    conn: conn,
    organization: organization
  } do
    assert {:ok, database} = Organizations.create_database_for_org(organization, mysql_attrs())

    {:ok, _lv, html} = live(conn, "/admin/databases/#{database.id}/show")

    assert html =~ "MySQL database connection"
    assert html =~ "Danger zone"
  end

  test "admin database modal deletes database and linked transponders", %{
    conn: conn,
    organization: organization
  } do
    assert {:ok, database} = Organizations.create_database_for_org(organization, mysql_attrs())

    {:ok, transponder} =
      Organizations.create_transponder_for_database(database, transponder_attrs("DB Total"))

    {:ok, lv, _html} = live(conn, "/admin/databases/#{database.id}/show")

    lv
    |> element("button[phx-click=\"delete_database\"]")
    |> render_click()

    assert_patch(lv, "/admin/databases")
    assert_raise Ecto.NoResultsError, fn -> Organizations.get_database!(database.id) end
    assert_raise Ecto.NoResultsError, fn -> Organizations.get_transponder!(transponder.id) end
  end

  test "admin database form component includes MySQL driver option", %{organization: organization} do
    html =
      render_component(FormComponent,
        id: "new-db-form",
        title: "New Database",
        action: :new,
        database: %Database{organization_id: organization.id},
        patch: "/admin/databases"
      )

    assert html =~ "Driver"
    assert html =~ "MySQL"
  end

  defp mysql_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        display_name: "Admin MySQL",
        driver: "mysql",
        host: "127.0.0.1",
        port: 3306,
        database_name: "admin_stats",
        username: "trifle",
        password: "secret"
      },
      overrides
    )
  end

  defp transponder_attrs(name) do
    %{
      "name" => name,
      "key" => "metric::#{System.unique_integer([:positive])}",
      "config" => %{
        "paths" => ["foo"],
        "expression" => "a",
        "response" => "total"
      }
    }
  end
end
