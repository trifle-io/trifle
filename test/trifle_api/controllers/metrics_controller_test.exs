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

    {:ok, database_token} =
      Organizations.create_database_token(%{database: database, name: "Read"})

    project = project_fixture(%{user: user})

    {:ok, read_project_token} =
      Organizations.create_project_token(%{
        project: project,
        name: "Read",
        read: true,
        write: false
      })

    {:ok, write_project_token} =
      Organizations.create_project_token(%{
        project: project,
        name: "Write",
        read: false,
        write: true
      })

    on_exit(fn -> File.rm(file_path) end)

    {
      :ok,
      database_token: database_token,
      read_project_token: read_project_token,
      write_project_token: write_project_token,
      timestamp: timestamp
    }
  end

  describe "GET /api/metrics" do
    test "returns 401 without token", %{conn: conn} do
      conn = conn |> api_conn() |> get(~p"/api/metrics")

      assert %{"errors" => %{"detail" => "Bad token"}} = json_response(conn, 401)
    end

    test "rejects write-only project tokens", %{conn: conn, write_project_token: token} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> get(~p"/api/metrics", %{key: "metrics.total"})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "accepts read project tokens and validates params", %{
      conn: conn,
      read_project_token: token
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> get(~p"/api/metrics", %{key: ""})

      assert %{"errors" => %{"detail" => "Bad request"}} = json_response(conn, 400)
    end

    test "returns series data for database tokens", %{
      conn: conn,
      database_token: token,
      timestamp: timestamp
    } do
      from = DateTime.add(timestamp, -60, :second) |> DateTime.to_iso8601()
      to = DateTime.add(timestamp, 60, :second) |> DateTime.to_iso8601()

      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> get(~p"/api/metrics", %{
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

  describe "POST /api/metrics" do
    test "rejects read-only project tokens", %{conn: conn, read_project_token: token} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> post(~p"/api/metrics", %{})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "rejects database tokens", %{conn: conn, database_token: token} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> post(~p"/api/metrics", %{})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    test "accepts write project tokens and validates params", %{
      conn: conn,
      write_project_token: token
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token.token)
        |> post(~p"/api/metrics", %{})

      assert %{"errors" => %{"detail" => "Bad request"}} = json_response(conn, 400)
    end
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
