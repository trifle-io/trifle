defmodule TrifleApp.Exports.DashboardLayoutTest do
  use Trifle.DataCase, async: true

  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations
  alias TrifleApp.Exports.DashboardLayout

  setup do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})
    {:ok, _} = Organizations.setup_database(database)

    dashboard_attrs = %{
      "name" => "Export Group Test",
      "key" => "export-group-#{System.unique_integer([:positive])}",
      "database_id" => database.id,
      "source_type" => "database",
      "source_id" => database.id,
      "default_timeframe" => "24h",
      "default_granularity" => "1h",
      "payload" => %{"grid" => []}
    }

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(user, membership, dashboard_attrs)

    {:ok, dashboard: dashboard, membership: membership}
  end

  test "full dashboard export preserves widget groups in the rendered grid", %{
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "group-1",
              "type" => "group",
              "title" => "Amazon US",
              "x" => 0,
              "y" => 0,
              "w" => 8,
              "h" => 6,
              "children" => [
                %{
                  "id" => "widget-1",
                  "type" => "text",
                  "title" => "Jobs",
                  "subtype" => "header",
                  "payload" => "<h2>Jobs</h2>",
                  "x" => 0,
                  "y" => 0,
                  "w" => 6,
                  "h" => 2
                },
                %{
                  "id" => "widget-2",
                  "type" => "text",
                  "title" => "Products",
                  "subtype" => "header",
                  "payload" => "<h2>Products</h2>",
                  "x" => 6,
                  "y" => 0,
                  "w" => 6,
                  "h" => 2
                }
              ]
            },
            %{
              "id" => "widget-3",
              "type" => "text",
              "title" => "Summary",
              "subtype" => "header",
              "payload" => "<h2>Summary</h2>",
              "x" => 8,
              "y" => 0,
              "w" => 4,
              "h" => 2
            }
          ]
        }
      })

    assert {:ok, layout} = DashboardLayout.build(dashboard)

    [group, widget] = layout.render.assigns.dashboard.payload["grid"]

    assert group["id"] == "group-1"
    assert group["type"] == "group"
    assert group["title"] == "Amazon US"
    assert Enum.map(group["children"], & &1["id"]) == ["widget-1", "widget-2"]

    assert widget["id"] == "widget-3"
  end

  test "single widget export finds a widget nested inside a group", %{
    dashboard: dashboard,
    membership: membership
  } do
    {:ok, dashboard} =
      Organizations.update_dashboard_for_membership(dashboard, membership, %{
        payload: %{
          "grid" => [
            %{
              "id" => "group-1",
              "type" => "group",
              "title" => "Amazon US",
              "x" => 0,
              "y" => 0,
              "w" => 8,
              "h" => 6,
              "children" => [
                %{
                  "id" => "widget-1",
                  "type" => "text",
                  "title" => "Jobs",
                  "subtype" => "header",
                  "payload" => "<h2>Jobs</h2>",
                  "x" => 0,
                  "y" => 0,
                  "w" => 6,
                  "h" => 2
                }
              ]
            }
          ]
        }
      })

    assert {:ok, layout} = DashboardLayout.build_widget(dashboard, "widget-1")

    assert layout.kind == :dashboard_widget
    assert layout.meta[:widget] == %{id: "widget-1"}

    [widget] = layout.render.assigns.dashboard.payload["grid"]

    assert widget["id"] == "widget-1"
    assert widget["x"] == 0
    assert widget["y"] == 0
    assert widget["w"] == 12
  end
end
