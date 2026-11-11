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

  describe "token scope" do
    setup context do
      other_path =
        Path.join(System.tmp_dir!(), "trifle-dashboard-other-#{Ecto.UUID.generate()}.sqlite")

      {:ok, other_database} =
        Organizations.create_database_for_org(context.organization, %{
          display_name: "Other DB",
          driver: "sqlite",
          file_path: other_path
        })

      {:ok, other_dashboard} =
        Organizations.create_dashboard_for_membership(context.user, context.membership, %{
          "name" => "Other source dashboard",
          "key" => "other",
          "visibility" => true,
          "source_type" => "database",
          "source_id" => other_database.id
        })

      read_only =
        create_scoped_token!(
          context.user,
          context.organization.id,
          :database,
          context.database.id,
          true,
          false
        )

      {:ok,
       other_database: other_database, other_dashboard: other_dashboard, read_only: read_only}
    end

    defp request(context, token) do
      context.conn |> api_conn() |> auth_conn(token, context.database.id)
    end

    test "a read-only token can read but not change dashboards of its source", context do
      dashboard = create_dashboard(context, nil)

      assert %{"data" => %{"id" => _}} =
               context
               |> request(context.read_only)
               |> get(~p"/api/v1/dashboards/#{dashboard.id}")
               |> json_response(200)

      for response <- [
            context
            |> request(context.read_only)
            |> put(~p"/api/v1/dashboards/#{dashboard.id}", %{dashboard: %{name: "Renamed"}}),
            context
            |> request(context.read_only)
            |> delete(~p"/api/v1/dashboards/#{dashboard.id}"),
            context
            |> request(context.read_only)
            |> post(~p"/api/v1/dashboards", %{dashboard: %{name: "New", key: "k"}})
          ] do
        assert response.status == 403
      end

      assert Organizations.get_dashboard!(dashboard.id).name == dashboard.name
    end

    test "a token for one source cannot see or change another source's dashboards", context do
      own = create_dashboard(context, nil)
      other = context.other_dashboard

      assert %{"data" => listed} =
               context
               |> request(context.token)
               |> get(~p"/api/v1/dashboards")
               |> json_response(200)

      ids = Enum.map(listed, & &1["id"])
      assert own.id in ids
      refute other.id in ids

      assert (context |> request(context.token) |> get(~p"/api/v1/dashboards/#{other.id}")).status ==
               404

      assert (context
              |> request(context.token)
              |> put(~p"/api/v1/dashboards/#{other.id}", %{dashboard: %{name: "Hijacked"}})).status ==
               404

      assert (context
              |> request(context.token)
              |> delete(~p"/api/v1/dashboards/#{other.id}")).status ==
               404

      assert Organizations.get_dashboard!(other.id).name == "Other source dashboard"
    end

    test "a token cannot create or re-point a dashboard at a source it has no grant for",
         context do
      own = create_dashboard(context, nil)

      create_conn =
        context
        |> request(context.token)
        |> post(~p"/api/v1/dashboards", %{
          dashboard: %{
            name: "Sneaky",
            key: "k",
            source_type: "database",
            source_id: context.other_database.id
          }
        })

      assert create_conn.status == 403

      update_conn =
        context
        |> request(context.token)
        |> put(~p"/api/v1/dashboards/#{own.id}", %{
          dashboard: %{source_type: "database", source_id: context.other_database.id}
        })

      assert update_conn.status == 403
      assert Organizations.get_dashboard!(own.id).source_id == context.database.id
    end

    test "naming a permitted source alongside a forbidden one is rejected", context do
      own = create_dashboard(context, nil)
      allowed = context.database.id
      forbidden = context.other_database.id

      # The saving code and the authorization could disagree about which of these
      # wins, so every combination must be refused, whichever key carries which.
      payloads = [
        %{
          source_type: "database",
          source_id: allowed,
          source: %{type: "database", id: forbidden}
        },
        %{
          source_type: "database",
          source_id: forbidden,
          source: %{type: "database", id: allowed}
        },
        %{source_type: "database", source_id: allowed, database_id: forbidden},
        %{database_id: allowed, source: %{type: "database", id: forbidden}},
        %{source: %{id: forbidden}},
        %{source_id: forbidden}
      ]

      for payload <- payloads do
        create_conn =
          context
          |> request(context.token)
          |> post(~p"/api/v1/dashboards", %{
            dashboard: Map.merge(%{name: "Sneaky", key: "k"}, payload)
          })

        assert create_conn.status == 403, "create accepted #{inspect(payload)}"

        update_conn =
          context
          |> request(context.token)
          |> put(~p"/api/v1/dashboards/#{own.id}", %{dashboard: payload})

        assert update_conn.status == 403, "update accepted #{inspect(payload)}"
      end

      assert Organizations.get_dashboard!(own.id).source_id == allowed

      refute Enum.any?(
               Organizations.list_all_dashboards_for_membership(context.user, context.membership),
               &(&1.name == "Sneaky")
             )
    end

    test "a new dashboard without a source is pinned to the token's source", context do
      conn =
        context
        |> request(context.token)
        |> post(~p"/api/v1/dashboards", %{dashboard: %{name: "Pinned", key: "k"}})

      assert %{"data" => %{"id" => id}} = json_response(conn, 201)
      assert Organizations.get_dashboard!(id).source_id == context.database.id
    end
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
