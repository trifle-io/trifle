defmodule TrifleApp.MonitorsLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Organizations
  alias TrifleApp.MonitorsLive.FormComponent

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})

    {:ok,
     conn: log_in_user(conn, user),
     user: user,
     organization: organization,
     membership: membership,
     database: database}
  end

  test "groups monitors into triggered, active, and paused sections", context do
    triggered = create_alert_monitor(context, "Triggered monitor", "alerts.triggered")
    active = create_alert_monitor(context, "Active monitor", "alerts.active")
    paused = create_alert_monitor(context, "Paused monitor", "alerts.paused")

    assert {:ok, triggered} =
             Monitors.update_monitor_for_membership(triggered, context.membership, %{
               "trigger_status" => "alerting"
             })

    assert {:ok, paused} =
             Monitors.update_monitor_for_membership(paused, context.membership, %{
               "status" => "paused",
               "trigger_status" => "alerting"
             })

    {:ok, view, _html} = live(context.conn, ~p"/monitors")

    assert monitor_ids(view, :triggered) == [triggered.id]
    assert monitor_ids(view, :active) == [active.id]
    assert monitor_ids(view, :paused) == [paused.id]

    assert has_element?(view, "#monitors-section-triggered", "Triggered")
    assert has_element?(view, "#monitors-section-active", "Active")
    assert has_element?(view, "#monitors-section-paused", "Paused")
  end

  test "omits empty sections", context do
    active = create_alert_monitor(context, "Only active monitor", "alerts.active")

    {:ok, view, _html} = live(context.conn, ~p"/monitors")

    assert monitor_ids(view, :active) == [active.id]
    refute has_element?(view, "#monitors-section-triggered")
    refute has_element?(view, "#monitors-section-paused")
  end

  test "sorts names in both directions and normalizes invalid URL parameters", context do
    alpha = create_alert_monitor(context, "alpha monitor", "metric.zulu")
    zulu = create_alert_monitor(context, "Zulu monitor", "metric.alpha")

    {:ok, view, _html} = live(context.conn, ~p"/monitors?sort=name&dir=desc")

    assert monitor_ids(view, :active) == [zulu.id, alpha.id]
    assert has_element?(view, "#monitor-sort option[value='name'][selected]")
    assert has_element?(view, "#monitor-sort-direction", "Z–A")

    view
    |> element("#monitor-sort-form")
    |> render_change(%{"sort" => "metric_key"})

    assert_patch(view, "/monitors?sort=metric_key&dir=desc")
    assert monitor_ids(view, :active) == [alpha.id, zulu.id]

    view
    |> element("#monitor-sort-direction")
    |> render_click()

    assert_patch(view, "/monitors?sort=metric_key&dir=asc")
    assert monitor_ids(view, :active) == [zulu.id, alpha.id]

    {:ok, invalid_view, _html} = live(context.conn, ~p"/monitors?sort=unknown&dir=sideways")

    assert monitor_ids(invalid_view, :active) == [alpha.id, zulu.id]
    assert has_element?(invalid_view, "#monitor-sort option[value='name'][selected]")
    assert has_element?(invalid_view, "#monitor-sort-direction", "A–Z")
  end

  test "sorts alerts and reports by their effective metric keys with missing keys last",
       context do
    alert = create_alert_monitor(context, "Alert monitor", "metrics.zulu")
    report = create_report_monitor(context, "Report monitor", "metrics.alpha")
    missing = create_report_monitor(context, "Missing dashboard", "metrics.middle")

    assert {:ok, _dashboard} = Organizations.delete_dashboard(missing.dashboard)

    {:ok, ascending_view, _html} =
      live(context.conn, ~p"/monitors?sort=metric_key&dir=asc")

    assert monitor_ids(ascending_view, :active) == [
             report.monitor.id,
             alert.id,
             missing.monitor.id
           ]

    {:ok, descending_view, _html} =
      live(context.conn, ~p"/monitors?sort=metric_key&dir=desc")

    assert monitor_ids(descending_view, :active) == [
             alert.id,
             report.monitor.id,
             missing.monitor.id
           ]
  end

  test "preserves sorting while opening, cancelling, and saving the new monitor modal", context do
    monitor = create_alert_monitor(context, "Active monitor", "metrics.alpha")

    {:ok, view, _html} = live(context.conn, ~p"/monitors?sort=metric_key&dir=desc")

    view
    |> element("a[aria-label='New Monitor']")
    |> render_click()

    assert_patch(view, "/monitors/new?sort=metric_key&dir=desc")
    assert has_element?(view, "#monitor-form")

    view
    |> element("#monitor-modal button", "Cancel")
    |> render_click()

    assert_patch(view, "/monitors?sort=metric_key&dir=desc")

    view
    |> element("a[aria-label='New Monitor']")
    |> render_click()

    send(view.pid, {FormComponent, {:saved, monitor}})

    assert_patch(view, "/monitors?sort=metric_key&dir=desc")
  end

  defp create_alert_monitor(context, name, metric_key) do
    {:ok, monitor} =
      Monitors.create_monitor_for_membership(context.user, context.membership, %{
        "name" => name,
        "type" => "alert",
        "alert_metric_key" => metric_key,
        "alert_metric_path" => "$.global",
        "alert_timeframe" => "15m",
        "alert_granularity" => "5m",
        "delivery_channels" => [
          %{"channel" => "email", "label" => "Primary", "target" => "alerts@example.com"}
        ],
        "source_type" => "database",
        "source_id" => context.database.id
      })

    monitor
  end

  defp create_report_monitor(context, name, metric_key) do
    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(context.user, context.membership, %{
        "name" => "#{name} dashboard",
        "key" => metric_key,
        "source_type" => "database",
        "source_id" => context.database.id,
        "database_id" => context.database.id,
        "default_timeframe" => "24h",
        "default_granularity" => "1h",
        "payload" => %{"grid" => []}
      })

    {:ok, monitor} =
      Monitors.create_monitor_for_membership(context.user, context.membership, %{
        "name" => name,
        "type" => "report",
        "dashboard_id" => dashboard.id,
        "report_settings" => %{
          "frequency" => "daily",
          "timeframe" => "24h",
          "granularity" => "1h"
        }
      })

    %{monitor: monitor, dashboard: dashboard}
  end

  defp monitor_ids(view, section) do
    view
    |> element("#monitors-list-#{section}")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("a[id^='monitor-card-']")
    |> Floki.attribute("id")
    |> Enum.map(&String.replace_prefix(&1, "monitor-card-", ""))
  end
end
