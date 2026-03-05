defmodule TrifleApi.MetricsControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  setup do
    user = user_fixture()

    {:ok, organization, _membership} =
      Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

    file_path = Path.join(System.tmp_dir!(), "trifle-api-#{Ecto.UUID.generate()}.sqlite")

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "API DB",
        driver: "sqlite",
        file_path: file_path
      })

    {:ok, _} = Organizations.setup_database(database)

    timestamp = DateTime.utc_now()
    stats_config = Database.stats_config(database)
    _ = Trifle.Stats.track("metrics.total", timestamp, %{"value" => 1}, stats_config)

    project = project_fixture(%{user: user})

    database_token =
      create_scoped_token!(user, organization.id, :database, database.id, true, false)

    read_project_token =
      create_scoped_token!(user, organization.id, :project, project.id, true, false)

    write_project_token =
      create_scoped_token!(user, organization.id, :project, project.id, false, true)

    on_exit(fn -> File.rm(file_path) end)

    {
      :ok,
      database: database,
      database_token: database_token,
      project: project,
      read_project_token: read_project_token,
      write_project_token: write_project_token,
      timestamp: timestamp
    }
  end

  describe "GET /api/v1/metrics" do
    test "returns 401 without token", %{conn: conn} do
      conn = conn |> api_conn() |> get(~p"/api/v1/metrics")

      assert %{"errors" => %{"detail" => "Bad token"}} = json_response(conn, 401)
    end

    test "returns 400 when source header is missing", %{conn: conn, write_project_token: token} do
      conn =
        conn
        |> api_conn()
        |> auth_conn_without_source(token)
        |> get(~p"/api/v1/metrics", %{key: "metrics.total"})

      assert %{"errors" => %{"detail" => "Missing X-Trifle-Source-Id header"}} =
               json_response(conn, 400)
    end

    test "rejects write-only project tokens", %{conn: conn, write_project_token: token, project: project} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> get(~p"/api/v1/metrics", %{key: "metrics.total"})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "accepts read project tokens and validates params", %{
      conn: conn,
      read_project_token: token,
      project: project
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> get(~p"/api/v1/metrics", %{key: ""})

      assert %{"errors" => %{"detail" => "Bad request"}} = json_response(conn, 400)
    end

    test "returns series data for database tokens", %{
      conn: conn,
      database_token: token,
      database: database,
      timestamp: timestamp
    } do
      from = DateTime.add(timestamp, -60, :second) |> DateTime.to_iso8601()
      to = DateTime.add(timestamp, 60, :second) |> DateTime.to_iso8601()

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, database.id)
        |> get(~p"/api/v1/metrics", %{
          key: "metrics.total",
          from: from,
          to: to,
          granularity: "1m"
        })

      assert %{"data" => %{"at" => at, "values" => values}} = json_response(conn, 200)
      assert is_list(at)
      assert is_list(values)
    end
  end

  describe "POST /api/v1/metrics" do
    test "rejects read-only project tokens", %{conn: conn, read_project_token: token, project: project} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "rejects database tokens", %{conn: conn, database_token: token, database: database} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, database.id)
        |> post(~p"/api/v1/metrics", %{})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "accepts write project tokens and validates params", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{})

      assert %{"errors" => %{"detail" => "Bad request"}} = json_response(conn, 400)
    end
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_conn(conn, token, source_id) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("x-trifle-source-id", source_id)
  end

  defp auth_conn_without_source(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp create_scoped_token!(user, organization_id, source_type, source_id, read, write) do
    permissions = scoped_permissions(source_type, source_id, read, write)

    {:ok, _record, value} =
      Organizations.create_organization_api_token(user, %{
        organization_id: organization_id,
        name: "API test token",
        permissions: permissions
      })

    value
  end

  defp scoped_permissions(source_type, source_id, read, write) do
    source_key = "#{source_type}:#{source_id}"

    %{
      "wildcard" => %{"read" => false, "write" => false},
      "sources" => %{
        source_key => %{"read" => read, "write" => write}
      }
    }
  end
end
