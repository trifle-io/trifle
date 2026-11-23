defmodule TrifleApp.MonitorLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Organizations
  alias Trifle.Stats.Source

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

    {:ok, view, html} = live(conn, ~p"/monitors/#{monitor.id}")

    assert html =~ "Latency Watch"
    assert html =~ "Not set"
    refute has_element?(view, ~s([data-role="explore-metric-key"]))
  end

  test "saves and clears an alert's wildcard values", %{
    conn: conn,
    monitor: monitor,
    membership: membership,
    database: database
  } do
    {:ok, _} = Organizations.setup_database(database)

    {:ok, monitor} =
      Monitors.update_monitor_for_membership(monitor, membership, %{
        alert_metric_path: "products.*"
      })

    config = database |> Source.from_database() |> Source.stats_config()
    config = %{config | buffer_enabled: false, storage: nil}

    assert {:ok, _} =
             Trifle.Stats.track(
               monitor.alert_metric_key,
               DateTime.add(DateTime.utc_now(), -60, :second),
               %{"products" => %{"basic" => 100, "enterprise" => 200}, "total" => 300},
               config
             )

    {:ok, view, _html} = live(conn, ~p"/monitors/#{monitor.id}")
    render_async(view)

    view |> element(~s(button[phx-click="new_alert"])) |> render_click()

    assert has_element?(view, "[role=combobox][name='alert[wildcard_filter_input]']")
    assert has_element?(view, ~s([data-suggestions='["basic","enterprise"]']))
    assert has_element?(view, "option[value=in]", "Match")
    assert has_element?(view, "option[value=not_in]", "Exclude")

    view
    |> form("#monitor-alert-form")
    |> render_submit(%{
      "alert" => %{
        "wildcard_filter_input" => " enterprise, basic ",
        "settings" => %{
          "threshold_value" => "1000",
          "wildcard_filter_operator" => "not_in",
          "wildcard_filter_values" => ["", "basic"]
        }
      }
    })

    [alert] = Monitors.list_alerts(monitor)
    assert alert.settings.wildcard_filter_operator == :not_in
    assert alert.settings.wildcard_filter_values == ["basic", "enterprise"]
    assert has_element?(view, "li p", "Excluding 2 paths")

    view |> element(~s(button[phx-click="edit_alert"])) |> render_click()
    assert has_element?(view, "option[value=not_in][selected]")

    assert has_element?(
             view,
             ~s([data-values='["basic","enterprise"]'])
           )

    view
    |> form("#monitor-alert-form")
    |> render_submit(%{
      "alert" => %{
        "settings" => %{"wildcard_filter_operator" => "in", "wildcard_filter_values" => ["basic"]}
      }
    })

    assert has_element?(view, "li p", "Matching 1 path")
    refute has_element?(view, "li p", "Excluding 2 paths")

    view |> element(~s(button[phx-click="edit_alert"])) |> render_click()

    view
    |> form("#monitor-alert-form")
    |> render_submit(%{"alert" => %{"settings" => %{"wildcard_filter_values" => [""]}}})

    assert Monitors.get_alert!(monitor, alert.id).settings.wildcard_filter_values == []
    refute has_element?(view, "li p", "Matching 1 path")
  end

  test "a range over the point limit shows the message instead of crashing", %{
    conn: conn,
    monitor: monitor,
    database: database
  } do
    {:ok, _} = Organizations.setup_database(database)
    Application.put_env(:trifle, :series_max_points, 2)
    on_exit(fn -> Application.delete_env(:trifle, :series_max_points) end)

    {:ok, view, _html} = live(conn, ~p"/monitors/#{monitor.id}")

    html = render_async(view, 5_000)

    assert html =~ "more than 2 data points"
    assert Process.alive?(view.pid)
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

  test "expanded insights stay below the FilterBar while granularity changes", %{
    conn: conn,
    monitor: monitor,
    database: database
  } do
    {:ok, _} = Organizations.setup_database(database)
    {:ok, view, _html} = live(conn, ~p"/monitors/#{monitor.id}")
    render_async(view)

    render_click(view, "expand_widget", %{"id" => Monitors.AlertSeries.source_widget_id(monitor)})
    assert has_element?(view, "#monitor_filter_bar-shortcuts ~ section#monitor-widget-workspace")
    assert has_element?(view, "#monitor-insights[inert]")
    assert has_element?(view, "#monitor-widget-workspace", "Source series")

    view |> element(~s([data-filter-bar-granularity="1d"])) |> render_click()
    assert_push_event(view, "monitor_widget_export_params", %{params: %{"granularity" => "1d"}})
    render_async(view)
    assert has_element?(view, "#monitor-widget-workspace", "Source series")

    view |> element("#monitor-widget-workspace [data-workspace-close]") |> render_click()
    refute has_element?(view, "#monitor-widget-workspace")
    refute has_element?(view, "#monitor-insights[inert]")
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

    explore_params = %{source_type: "database", source_id: database.id, key: "requests.eu.worker"}
    explore_path = ~p"/explore?#{explore_params}"

    assert has_element?(
             view,
             ~s([data-role="explore-metric-key"][href="#{explore_path}"]),
             "requests.eu.worker"
           )

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
