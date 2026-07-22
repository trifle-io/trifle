defmodule TrifleApi.MetricsControllerTest do
  use TrifleApp.ConnCase

  import Ecto.Query
  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures
  import TrifleApi.TestHelpers

  alias Trifle.Billing.Entitlement
  alias Trifle.Organizations
  alias Trifle.Repo

  setup do
    previous_metrics_module = Application.get_env(:trifle, :metrics_module)
    Application.put_env(:trifle, :metrics_module, Trifle.MetricsMock)
    start_supervised!(Trifle.MetricsMock)
    Trifle.MetricsMock.reset()

    user = user_fixture()

    {:ok, organization, _membership} =
      Organizations.create_organization_with_owner(%{name: "Acme Inc"}, user)

    app_entitlement_fixture(organization)

    file_path = Path.join(System.tmp_dir!(), "trifle-api-#{Ecto.UUID.generate()}.sqlite")

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "API DB",
        driver: "sqlite",
        file_path: file_path
      })

    project = project_fixture(%{user: user})
    project_subscription_fixture(project)

    database_token =
      create_scoped_token!(user, organization.id, :database, database.id, true, false)

    read_project_token =
      create_scoped_token!(user, organization.id, :project, project.id, true, false)

    write_project_token =
      create_scoped_token!(user, organization.id, :project, project.id, false, true)

    on_exit(fn ->
      _ = File.rm(file_path)

      if is_nil(previous_metrics_module) do
        Application.delete_env(:trifle, :metrics_module)
      else
        Application.put_env(:trifle, :metrics_module, previous_metrics_module)
      end
    end)

    {
      :ok,
      database: database,
      database_token: database_token,
      project: project,
      read_project_token: read_project_token,
      write_project_token: write_project_token
    }
  end

  describe "GET /api/v1/metrics" do
    test "returns 401 without token", %{conn: conn} do
      conn = conn |> api_conn() |> get(~p"/api/v1/metrics")

      assert %{"errors" => %{"detail" => "Bad token"}} = json_response(conn, 401)
      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
    end

    test "returns 400 when source header is missing", %{conn: conn, write_project_token: token} do
      conn =
        conn
        |> api_conn()
        |> auth_conn_without_source(token)
        |> get(~p"/api/v1/metrics", %{key: "metrics.total"})

      assert %{"errors" => %{"detail" => "Missing X-Trifle-Source-Id header"}} =
               json_response(conn, 400)

      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
    end

    test "rejects write-only project tokens", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> get(~p"/api/v1/metrics", %{key: "metrics.total"})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
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
      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
    end

    test "returns series data for database tokens", %{
      conn: conn,
      database_token: token,
      database: database
    } do
      timestamp = DateTime.utc_now() |> DateTime.truncate(:second)

      Trifle.MetricsMock.stub_fetch_series(fn _source, key, _from, _to, _granularity, _opts ->
        assert key == "metrics.total"
        {:ok, %{series: %{at: [timestamp], values: [1]}}}
      end)

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
      assert at == [DateTime.to_iso8601(timestamp)]
      assert values == [1]
      assert %{fetch_series: 1, track: 0} = Trifle.MetricsMock.calls()
    end

    test "rejects inactive database sources after billing is removed", %{
      conn: conn,
      database_token: token,
      database: database
    } do
      Repo.delete_all(
        from entitlement in Entitlement,
          where: entitlement.organization_id == ^database.organization_id
      )

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, database.id)
        |> get(~p"/api/v1/metrics", %{key: "metrics.total"})

      assert %{
               "errors" => %{
                 "detail" => "source_inactive",
                 "reason" => "missing_app_subscription"
               }
             } =
               json_response(conn, 403)
    end
  end

  describe "POST /api/v1/metrics" do
    test "rejects read-only project tokens", %{
      conn: conn,
      read_project_token: token,
      project: project
    } do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
    end

    test "rejects database tokens", %{conn: conn, database_token: token, database: database} do
      conn =
        conn
        |> api_conn()
        |> auth_conn(token, database.id)
        |> post(~p"/api/v1/metrics", %{})

      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
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
      assert %{fetch_series: 0, track: 0} = Trifle.MetricsMock.calls()
    end

    test "tracks metrics by default and forwards untracked", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      parent = self()

      Trifle.MetricsMock.stub_track(fn key, at, values, _config, opts ->
        send(parent, {:tracked, key, at, values, opts})
        :ok
      end)

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{
          key: "orders",
          at: "2026-07-22T12:00:00Z",
          values: %{count: 1},
          untracked: true
        })

      assert %{"data" => %{"created" => "ok"}} = json_response(conn, 201)
      assert_received {:tracked, "orders", %DateTime{}, %{"count" => 1}, [untracked: true]}
      assert %{track: 1, assert: 0} = Trifle.MetricsMock.calls()
    end

    test "dispatches assert operations", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      parent = self()

      Trifle.MetricsMock.stub_assert(fn key, at, values, _config, opts ->
        send(parent, {:asserted, key, at, values, opts})
        :ok
      end)

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{
          operation: "assert",
          key: "state::orders",
          at: "2026-07-22T12:00:00Z",
          values: %{pending: 4}
        })

      assert %{"data" => %{"created" => "ok"}} = json_response(conn, 201)

      assert_received {:asserted, "state::orders", %DateTime{}, %{"pending" => 4},
                       [untracked: false]}

      assert %{track: 0, assert: 1} = Trifle.MetricsMock.calls()
    end

    test "accepts gzip-compressed metric writes", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      body =
        Jason.encode!(%{
          operation: "track",
          key: "orders",
          at: "2026-07-22T12:00:00Z",
          values: %{count: 1}
        })

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-encoding", "gzip")
        |> post(~p"/api/v1/metrics", :zlib.gzip(body))

      assert %{"data" => %{"created" => "ok"}} = json_response(conn, 201)
      assert %{track: 1} = Trifle.MetricsMock.calls()
    end

    test "rejects invalid operations and untracked values", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      invalid_operation =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{
          operation: "delete",
          key: "orders",
          at: "2026-07-22T12:00:00Z",
          values: %{count: 1}
        })

      assert json_response(invalid_operation, 400)

      invalid_untracked =
        build_conn()
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{
          key: "orders",
          at: "2026-07-22T12:00:00Z",
          values: %{count: 1},
          untracked: "true"
        })

      assert json_response(invalid_untracked, 400)
      assert %{track: 0, assert: 0} = Trifle.MetricsMock.calls()
    end

    test "returns 500 when metric storage fails", %{
      conn: conn,
      write_project_token: token,
      project: project
    } do
      Trifle.MetricsMock.stub_track({:error, :unavailable})

      conn =
        conn
        |> api_conn()
        |> auth_conn(token, project.id)
        |> post(~p"/api/v1/metrics", %{
          key: "orders",
          at: "2026-07-22T12:00:00Z",
          values: %{count: 1}
        })

      assert json_response(conn, 500)
    end
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_conn(conn, token, source_id) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("x-trifle-source-id", to_string(source_id))
  end

  defp auth_conn_without_source(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
