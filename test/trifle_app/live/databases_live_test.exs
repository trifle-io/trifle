defmodule TrifleApp.DatabasesLiveTest do
  use TrifleApp.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Billing.Entitlement
  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Repo

  setup %{conn: conn} do
    on_exit(Trifle.ConfigFixtures.enable_saas_with_projects())

    user = Trifle.AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)

    {:ok, conn: log_in_user(conn, user), organization: organization}
  end

  test "new database form exposes MySQL driver option", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/dbs/new")

    assert html =~ "Driver"
    assert html =~ "MySQL"
  end

  test "exempt organization owner can create and use a database without a subscription", %{
    conn: conn,
    organization: organization
  } do
    assert {:ok, _} = Trifle.Billing.set_app_subscription_exempt(organization.id, true)
    assert Trifle.Billing.get_scope_subscription(organization.id, "app", nil) == nil

    {:ok, lv, html} = live(conn, ~p"/dbs")
    assert html =~ "New Database"
    refute html =~ "Activate subscription"

    lv |> element("a[aria-label='New Database']") |> render_click()
    assert_patch(lv, ~p"/dbs/new")

    lv
    |> form("#database-form", database: %{driver: "mysql"})
    |> render_change()

    lv
    |> form("#database-form", database: mysql_attrs(%{display_name: "Internal metrics"}))
    |> render_submit()

    assert_patch(lv, ~p"/dbs")
    assert [database] = Organizations.list_databases_for_org(organization.id)
    assert database.display_name == "Internal metrics"
    assert %{active?: true} = Trifle.Billing.source_access_status(:database, database)
    assert render(lv) =~ "Internal metrics"
    refute render(lv) =~ "Subscription required"

    {:ok, _view, _html} = live(conn, ~p"/dbs/#{database.id}/transponders")
  end

  test "ordinary owner without a subscription cannot open database creation", %{
    conn: conn,
    organization: organization
  } do
    assert {:ok, _} = Trifle.Billing.refresh_entitlements!(organization.id)
    assert {:error, {_kind, %{to: "/dbs", flash: flash}}} = live(conn, ~p"/dbs/new")
    assert flash["error"] =~ "An active organization subscription is required"
  end

  test "exemption preserves owner-only database creation", %{conn: conn, organization: org} do
    assert {:ok, _} = Trifle.Billing.set_app_subscription_exempt(org.id, true)

    for role <- ["admin", "member"] do
      user = Trifle.AccountsFixtures.user_fixture()
      {:ok, _membership} = Organizations.create_membership(org, user, role)
      member_conn = conn |> recycle() |> log_in_user(user)
      assert {:error, {_kind, %{to: "/dbs", flash: flash}}} = live(member_conn, ~p"/dbs/new")
      assert flash["error"] == "Only organization owners can create databases."
    end
  end

  test "new database authorization remains owner-only", %{conn: conn, organization: organization} do
    for role <- ["admin", "member"] do
      user = Trifle.AccountsFixtures.user_fixture()
      {:ok, _membership} = Organizations.create_membership(organization, user, role)
      member_conn = conn |> recycle() |> log_in_user(user)
      assert {:error, {_kind, %{to: "/dbs", flash: flash}}} = live(member_conn, ~p"/dbs/new")
      assert flash["error"] == "Only organization owners can create databases."
    end
  end

  test "new database form exposes secure connection methods for network drivers", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{"database" => %{"driver" => "mysql"}})

    assert html =~ "Connection Method"
    assert html =~ "Direct + IP allowlist"
    assert html =~ "SSH tunnel"
    assert html =~ "Private Connector"
    assert html =~ "Allowlist Trifle Cloud egress"
  end

  test "PostgreSQL form exposes optional Trifle Traces configuration", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{
        "database" => %{"driver" => "postgres", "connection_method" => "direct"}
      })

    assert html =~ "Trifle Traces"
    assert html =~ "Add Traces"

    html =
      lv
      |> element("button[phx-click=\"add_traces\"]")
      |> render_click()

    assert html =~ "Index table or collection"
    assert html =~ "S3-compatible object storage"
    assert html =~ "Retention days"
  end

  test "Private Connector remains Stats-only", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{
        "database" => %{"driver" => "postgres", "connection_method" => "connector"}
      })

    assert html =~ "Trifle Traces"
    assert html =~ "Unavailable"
    assert html =~ "Private Connector remains Stats-only"
  end

  test "S3 secret access key validation errors render beside the field", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    lv
    |> element("#database-form")
    |> render_change(%{"database" => %{"driver" => "postgres"}})

    lv |> element("button[phx-click='add_traces']") |> render_click()

    html =
      lv
      |> element("#database-form")
      |> render_change(%{
        "database" => %{
          "driver" => "postgres",
          "connection_method" => "direct",
          "trace_config" => %{
            "index_name" => "trifle_traces",
            "data_driver" => "s3",
            "data_buckets" => ["traces"],
            "data_region" => "us-east-1",
            "data_prefix" => "traces",
            "retention_days" => 7,
            "gzip" => true
          },
          "trace_secret_access_key" => %{"invalid" => "not a string"}
        }
      })

    doc = Floki.parse_document!(html)

    assert Floki.find(doc, "input[name='database[trace_secret_access_key]'] + p")
           |> Floki.text() == "is invalid"

    refute html =~ "not a string"
  end

  test "private connector method prompts for connector creation when none exist", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{
        "database" => %{"driver" => "mysql", "connection_method" => "connector"}
      })

    assert html =~ "Create a private connector before selecting this connection method."
  end

  test "ssh tunnel method shows bastion fields and generated public key", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{
        "database" => %{"driver" => "mysql", "connection_method" => "ssh_tunnel"}
      })

    assert html =~ "Bastion Host"
    assert html =~ "Host Key Fingerprint"
    assert html =~ "Trifle Public Key"
    assert html =~ "ssh-rsa"
  end

  test "private connector method appears when the organization has a connector", %{
    conn: conn,
    organization: organization
  } do
    {connector, _token} = organization_connector_with_token_fixture(%{organization: organization})
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{
        "database" => %{"driver" => "mysql", "connection_method" => "connector"}
      })

    assert html =~ "Private Connector"
    assert html =~ connector.name
  end

  test "new database form shows sqlite upload field when sqlite driver selected", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dbs/new")

    html =
      lv
      |> element("#database-form")
      |> render_change(%{"database" => %{"driver" => "sqlite"}})

    assert html =~ "SQLite File Upload"
    assert html =~ "Beginning of Week"
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
    assert html =~ "Direct"
    assert html =~ "Beginning of week"
    assert html =~ "Monday"
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

  test "database settings shows and removes Traces without deleting external data", %{
    conn: conn,
    organization: organization
  } do
    trace_path = Path.join(System.tmp_dir!(), "settings-traces-#{Ecto.UUID.generate()}")

    assert {:ok, database} =
             Organizations.create_database_for_org(organization, %{
               display_name: "Postgres traces",
               driver: "postgres",
               host: "postgres",
               port: 5432,
               database_name: Trifle.Repo.config()[:database],
               username: Trifle.Repo.config()[:username],
               password: Trifle.Repo.config()[:password],
               trace_config: %{
                 "index_name" => "settings_traces",
                 "data_driver" => "file",
                 "data_path" => trace_path,
                 "retention_days" => 7,
                 "gzip" => true
               }
             })

    File.mkdir_p!(trace_path)
    sentinel = Path.join(trace_path, "keep-me")
    File.write!(sentinel, "trace payload")
    on_exit(fn -> File.rm_rf!(trace_path) end)

    {:ok, lv, html} = live(conn, ~p"/dbs/#{database.id}/settings")
    assert html =~ "Stats + Traces"
    assert html =~ "Remove Traces"

    lv
    |> element("button[phx-click=\"remove_traces\"]")
    |> render_click()

    updated = Organizations.get_database!(database.id)
    refute Database.traces_configured?(updated)
    assert File.exists?(sentinel)
  end

  test "inactive databases remain visible with a billing CTA", %{
    conn: conn,
    organization: organization
  } do
    assert {:ok, database} =
             Organizations.create_database_for_org(
               organization,
               mysql_attrs(%{display_name: "Inactive DB"})
             )

    Repo.delete_all(
      from entitlement in Entitlement, where: entitlement.organization_id == ^organization.id
    )

    {:ok, _lv, html} = live(conn, ~p"/dbs")

    assert html =~ database.display_name
    assert html =~ "Subscription required"
    assert html =~ "Activate subscription"

    app_entitlement_fixture(organization)

    {:ok, _lv, html} = live(conn, ~p"/dbs")

    assert html =~ database.display_name
    refute html =~ "Subscription required"
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
