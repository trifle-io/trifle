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

  test "new database form shows sqlite upload field when sqlite driver selected", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("form")
      |> render_change(%{"database" => %{"driver" => "sqlite"}})

    assert html =~ "SQLite File Upload"
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

  test "database edit modal shows sqlite upload field", %{conn: conn, organization: organization} do
    sqlite_path = Path.join(System.tmp_dir!(), "settings-sqlite-#{Ecto.UUID.generate()}.sqlite")
    on_exit(fn -> File.rm(sqlite_path) end)

    assert {:ok, database} =
             Organizations.create_database_for_org(organization, %{
               display_name: "SQLite Source",
               driver: "sqlite",
               file_path: sqlite_path
             })

    {:ok, lv, _html} = live(conn, ~p"/dbs/#{database.id}/settings")

    html =
      lv
      |> element("button[phx-click=\"edit\"]")
      |> render_click()

    assert html =~ "SQLite File Upload"
  end

  test "database settings renders nested config values without crashing", %{
    conn: conn,
    organization: organization
  } do
    sqlite_path =
      Path.join(System.tmp_dir!(), "settings-nested-sqlite-#{Ecto.UUID.generate()}.sqlite")

    File.write!(sqlite_path, "sqlite")
    on_exit(fn -> File.rm(sqlite_path) end)

    assert {:ok, database} =
             Organizations.create_database_for_org(organization, %{
               display_name: "SQLite Nested Config",
               driver: "sqlite",
               file_path: sqlite_path,
               config: %{
                 "table_name" => "trifle_stats",
                 "sqlite_storage" => %{
                   "backend" => "s3",
                   "bucket" => "trifle-sqlite-files"
                 }
               }
             })

    {:ok, _lv, html} = live(conn, ~p"/dbs/#{database.id}/settings")

    assert html =~ "Configuration options"
    assert html =~ "Sqlite Storage"
    assert html =~ "backend"
    assert html =~ "trifle-sqlite-files"
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
