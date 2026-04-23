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

    {:ok, conn: log_in_user(conn, user), monitor: monitor, database: database}
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
    refute html =~ "top: 33%;"
  end
end
