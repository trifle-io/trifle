defmodule TrifleApp.MonitorLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Organizations

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})

    {:ok, monitor} =
      Monitors.create_monitor_for_membership(user, membership, %{
        "name" => "Latency Watch",
        "type" => "alert",
        "description" => "Keeps an eye on API latency",
        "alert_metric_key" => "latency.p95",
        "alert_metric_path" => "$.global",
        "alert_timeframe" => "15m",
        "alert_granularity" => "5m",
        "delivery_channels" => [
          %{"channel" => "email", "label" => "Primary", "target" => "alerts@example.com"}
        ],
        "source_type" => "database",
        "source_id" => database.id
      })

    {:ok,
     conn: log_in_user(conn, user),
     monitor: monitor,
     database: database,
     user: user,
     membership: membership}
  end

  test "renders when the source has been removed", %{
    conn: conn,
    monitor: monitor,
    database: database
  } do
    assert {:ok, _deleted_database} = Organizations.delete_database(database)

    {:ok, _view, html} = live(conn, ~p"/monitors/#{monitor.id}")

    assert html =~ "Latency Watch"
    assert html =~ "Not set"
  end

  test "renders the shared filter bar without the old insights overlay shell", %{
    conn: conn,
    monitor: monitor
  } do
    {:ok, view, html} = live(conn, ~p"/monitors/#{monitor.id}")

    assert has_element?(view, "#smart_timeframe")
    refute has_element?(view, "#monitor_filter_bar-attachment")
    refute html =~ "top: 33%;"
  end

  test "report segment filters update the preview and exports without saving monitor defaults", %{
    conn: conn,
    user: user,
    membership: membership,
    database: database
  } do
    {:ok, _} = Organizations.setup_database(database)

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(user, membership, %{
        "name" => "Segmented report",
        "key" => "requests.(region).(service)",
        "source_type" => "database",
        "source_id" => database.id,
        "database_id" => database.id,
        "payload" => %{"grid" => []},
        "segments" => [
          %{
            "name" => "region",
            "label" => "Region",
            "type" => "select",
            "default_value" => "eu",
            "groups" => [
              %{
                "items" => [
                  %{"value" => "eu", "label" => "Europe"},
                  %{"value" => "us", "label" => "US"}
                ]
              }
            ]
          },
          %{"name" => "service", "label" => "Service", "type" => "text", "default_value" => "api"}
        ]
      })

    {:ok, monitor} =
      Monitors.create_monitor_for_membership(user, membership, %{
        "name" => "Segmented report",
        "type" => "report",
        "dashboard_id" => dashboard.id,
        "segment_values" => %{"region" => "us", "service" => "web"},
        "report_settings" => %{
          "frequency" => "daily",
          "timeframe" => "24h",
          "granularity" => "1h"
        }
      })

    {:ok, view, _} = live(conn, ~p"/monitors/#{monitor.id}")
    render_async(view)

    attachment = "#monitor_filter_bar-shortcuts.sticky > #monitor_filter_bar-attachment"
    assert has_element?(view, "#{attachment} #monitor-segments-form")
    assert has_element?(view, "#{attachment} option[value='us'][selected]")
    assert has_element?(view, "#{attachment} input[value='web']")

    view
    |> form("#monitor-segments-form", %{segments: %{region: "eu", service: "worker"}})
    |> render_change()

    assert_push_event(view, "monitor_widget_export_params", %{
      params: %{
        "key" => "requests.eu.worker",
        "segments" => %{"region" => "eu", "service" => "worker"}
      }
    })

    render_async(view)
    assert has_element?(view, "#{attachment} option[value='eu'][selected]")
    assert has_element?(view, "#{attachment} input[value='worker']")
    assert render(view) =~ "requests.eu.worker"

    view
    |> form("#monitor-segments-form", %{segments: %{region: "us", service: ""}})
    |> render_submit()

    assert_push_event(view, "monitor_widget_export_params", %{
      params: %{"key" => "requests.us.", "segments" => %{"region" => "us", "service" => ""}}
    })

    render_async(view)
    assert has_element?(view, "#{attachment} input[value='']")

    assert Monitors.get_monitor_for_membership!(membership, monitor.id).segment_values ==
             %{"region" => "us", "service" => "web"}
  end
end
