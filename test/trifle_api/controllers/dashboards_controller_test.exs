defmodule TrifleApi.DashboardsControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import TrifleApi.TestHelpers

  alias Trifle.Organizations
  alias Trifle.Organizations.DashboardTemplateRef

  setup do
    user = user_fixture()
    unique = System.unique_integer([:positive])

    {:ok, organization, membership} =
      Organizations.create_organization_with_owner(%{name: "Dashboard API #{unique}"}, user)

    app_entitlement_fixture(organization)

    file_path =
      Path.join(System.tmp_dir!(), "trifle-dashboard-api-#{Ecto.UUID.generate()}.sqlite")

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "Dashboard API DB",
        driver: "sqlite",
        file_path: file_path
      })

    token = create_scoped_token!(user, organization.id, :database, database.id, true, true)

    on_exit(fn -> File.rm(file_path) end)

    {:ok,
     user: user,
     organization: organization,
     membership: membership,
     database: database,
     token: token}
  end

  test "returns effective template metadata and versioned payload", context do
    template = create_template(context)
    dashboard = create_dashboard(context, DashboardTemplateRef.encode(:user, template.id))

    conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> get(~p"/api/v1/dashboards/#{dashboard.id}")

    assert %{"data" => data} = json_response(conn, 200)
    assert data["template_id"] == "user:#{template.id}"
    assert data["template_type"] == "user"
    assert data["template_name"] == template.name
    assert data["template_version"] == 1
    assert data["template_read_only"] == false
    assert data["payload"] == template.payload
  end

  test "requires dashboard_version and returns 409 for stale local payload writes", context do
    dashboard = create_dashboard(context, nil)

    missing_version_conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: %{"grid" => [%{"id" => "missing-version"}]}}
      })

    assert %{"errors" => %{"dashboard_version" => [_message]}} =
             json_response(missing_version_conn, 422)

    for invalid_version <- [nil, "", "1.0", "1x", %{}] do
      invalid_version_conn =
        context.conn
        |> api_conn()
        |> auth_conn(context.token, context.database.id)
        |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
          dashboard: %{
            payload: %{"grid" => [%{"id" => "invalid-version"}]},
            dashboard_version: invalid_version
          }
        })

      assert %{"errors" => %{"dashboard_version" => [_message]}} =
               json_response(invalid_version_conn, 422)
    end

    payload = %{"grid" => [%{"id" => "updated"}]}

    updated_conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: payload, dashboard_version: 1}
      })

    assert %{"data" => %{"payload" => ^payload, "dashboard_version" => 2}} =
             json_response(updated_conn, 200)

    stale_conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: %{"grid" => []}, dashboard_version: 1}
      })

    assert %{"errors" => %{"dashboard_version" => [_message]}} =
             json_response(stale_conn, 409)
  end

  test "requires template_version and returns 409 for stale linked payload writes", context do
    template = create_template(context)
    dashboard = create_dashboard(context, DashboardTemplateRef.encode(:user, template.id))

    missing_version_conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: %{"grid" => [%{"id" => "missing-version"}]}}
      })

    assert %{"errors" => %{"template_version" => [_message]}} =
             json_response(missing_version_conn, 422)

    for invalid_version <- [nil, "", "1.0", "1x", %{}] do
      invalid_version_conn =
        context.conn
        |> api_conn()
        |> auth_conn(context.token, context.database.id)
        |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
          dashboard: %{
            payload: %{"grid" => [%{"id" => "invalid-version"}]},
            template_version: invalid_version
          }
        })

      assert %{"errors" => %{"template_version" => [_message]}} =
               json_response(invalid_version_conn, 422)
    end

    payload = %{"grid" => [%{"id" => "updated"}]}

    updated_conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: payload, template_version: 1}
      })

    assert %{"data" => %{"payload" => ^payload, "template_version" => 2}} =
             json_response(updated_conn, 200)

    stale_conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: %{"grid" => []}, template_version: 1}
      })

    assert %{"errors" => %{"template_version" => [_message]}} =
             json_response(stale_conn, 409)
  end

  test "rejects system template payload writes", context do
    dashboard = create_dashboard(context, "system:blank")

    conn =
      context.conn
      |> api_conn()
      |> auth_conn(context.token, context.database.id)
      |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{
        dashboard: %{payload: %{"grid" => [%{"id" => "blocked"}]}}
      })

    assert %{"errors" => %{"payload" => [_message]}} = json_response(conn, 422)
  end

  defp create_template(context) do
    {:ok, template} =
      Organizations.create_dashboard_template(context.user, context.membership, %{
        name: "Shared API template",
        payload: %{"grid" => [%{"id" => "original"}]}
      })

    template
  end

  defp create_dashboard(context, template_id) do
    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(context.user, context.membership, %{
        name: "Visible template dashboard",
        key: "api.dashboard.#{System.unique_integer([:positive])}",
        visibility: true,
        source_type: "database",
        source_id: context.database.id,
        database_id: context.database.id,
        default_timeframe: "24h",
        default_granularity: "1h",
        template_id: template_id
      })

    dashboard
  end

  defp api_conn(conn) do
    put_req_header(conn, "accept", "application/json")
  end

  defp auth_conn(conn, token, source_id) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("x-trifle-source-id", source_id)
  end
end
