defmodule TrifleApp.DashboardLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})

    dashboard_attrs = %{
      "name" => "Widget Workspace Test",
      "key" => "workspace-#{System.unique_integer([:positive])}",
      "database_id" => database.id,
      "source_type" => "database",
      "source_id" => database.id,
      "default_timeframe" => "24h",
      "default_granularity" => "1m",
      "payload" => %{
        "grid" => [
          %{
            "id" => "widget-1",
            "type" => "text",
            "title" => "Original Title",
            "subtype" => "header",
            "payload" => "<h2>Hello</h2>",
            "x" => 0,
            "y" => 0,
            "w" => 4,
            "h" => 2
          }
        ]
      }
    }

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(user, membership, dashboard_attrs)

    {:ok, conn: log_in_user(conn, user), dashboard: dashboard}
  end

  test "opens workspace in edit mode and supports tab toggling", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    refute has_element?(view, "#widget-workspace-modal")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})
    assert has_element?(view, "#widget-workspace-modal")
    assert has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"edit\"]")

    render_click(view, "set_widget_workspace_tab", %{"tab" => "summary"})
    assert has_element?(view, "#widget-workspace-modal button[phx-value-tab=\"summary\"]")
  end

  test "shows discard confirmation for unsaved changes and can cancel/confirm close", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_change(view, "widget_editor_change", %{
      "widget_id" => "widget-1",
      "widget_type" => "text",
      "widget_title" => "Updated Title",
      "text_subtype" => "header",
      "text_payload" => "<h2>Hello</h2>"
    })

    render_click(view, "request_close_widget_workspace", %{})

    assert has_element?(
             view,
             "#widget-workspace-modal",
             "You have unsaved changes. Discard them and close?"
           )

    render_click(view, "cancel_close_widget_workspace", %{})
    assert has_element?(view, "#widget-workspace-modal")

    render_click(view, "confirm_close_widget_workspace", %{})
    refute has_element?(view, "#widget-workspace-modal")
  end

  test "updates workspace preview title immediately while editing", %{
    conn: conn,
    dashboard: dashboard
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboards/#{dashboard.id}")

    render_click(view, "open_widget_editor", %{"id" => "widget-1"})

    render_change(view, "widget_editor_change", %{
      "widget_id" => "widget-1",
      "widget_type" => "text",
      "widget_title" => "Live Preview Title",
      "text_subtype" => "header",
      "text_payload" => "<h2>Hello</h2>"
    })

    assert has_element?(view, "#widget-workspace-modal", "Live Preview Title")
  end
end
