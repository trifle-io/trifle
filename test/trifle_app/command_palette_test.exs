defmodule TrifleApp.CommandPaletteTest do
  use Trifle.DataCase

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Organizations
  alias TrifleApp.CommandPalette

  setup do
    original_projects_enabled =
      if Application.get_env(:trifle, :projects_enabled, :__missing__) == :__missing__ do
        :__missing__
      else
        Application.get_env(:trifle, :projects_enabled)
      end

    on_exit(fn ->
      case original_projects_enabled do
        :__missing__ -> Application.delete_env(:trifle, :projects_enabled)
        value -> Application.put_env(:trifle, :projects_enabled, value)
      end
    end)

    Application.put_env(:trifle, :projects_enabled, true)

    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    membership = Organizations.get_membership_for_user(user)

    database =
      database_fixture(%{
        organization: organization,
        display_name: "Analytics Warehouse"
      })

    {:ok, dashboard_group} =
      Organizations.create_dashboard_group_for_membership(membership, %{
        name: "Revenue Reports"
      })

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(user, membership, %{
        "name" => "Revenue Overview",
        "key" => "revenue",
        "database_id" => database.id,
        "source_type" => "database",
        "source_id" => database.id,
        "group_id" => dashboard_group.id
      })

    :ok = Organizations.record_dashboard_visit(user, membership, dashboard)

    {:ok, monitor} =
      Monitors.create_monitor_for_membership(user, membership, %{
        "name" => "Latency Watch",
        "type" => "alert",
        "status" => "active",
        "trigger_status" => "alerting",
        "alert_metric_key" => "latency.p95",
        "alert_metric_path" => "$.global",
        "alert_timeframe" => "15m",
        "alert_granularity" => "5m",
        "source_type" => "database",
        "source_id" => database.id
      })

    project =
      project_fixture(%{
        user: user,
        organization: organization,
        name: "Search Project"
      })

    {:ok,
     user: user,
     membership: membership,
     database: database,
     dashboard: dashboard,
     monitor: monitor,
     project: project}
  end

  test "builds default and searchable command palette items with scoped routes", %{
    user: user,
    membership: membership,
    database: database,
    dashboard: dashboard,
    monitor: monitor,
    project: project
  } do
    items = CommandPalette.items(user, membership)

    assert find_item(items, "action:home")["to"] == "/"
    assert find_item(items, "action:home")["default_section"] == "Actions"

    assert find_item(items, "action:baker")["action"] == "chat"
    assert find_item(items, "action:baker")["default_section"] == "Actions"

    recent_dashboard_item = find_item(items, "recent:dashboard:#{dashboard.id}")
    assert recent_dashboard_item["default_section"] == "Recent"
    assert recent_dashboard_item["searchable"] == false
    assert recent_dashboard_item["title"] == "Revenue Reports / Revenue Overview"

    assert find_item(items, "triggered:monitor:#{monitor.id}")["default_section"] == "Triggered"
    assert find_item(items, "triggered:monitor:#{monitor.id}")["to"] == "/monitors/#{monitor.id}"

    dashboard_item = find_item(items, "dashboard:#{dashboard.id}")
    assert dashboard_item["title"] == "Revenue Reports / Revenue Overview"
    assert dashboard_item["search_section"] == "Dashboards"
    assert dashboard_item["default_section"] == nil
    assert dashboard_item["to"] == "/dashboards/#{dashboard.id}"

    assert find_item(items, "monitor:#{monitor.id}")["to"] == "/monitors/#{monitor.id}"
    assert find_item(items, "database:#{database.id}")["to"] == "/dbs/#{database.id}/transponders"

    assert find_item(items, "project:#{project.id}")["to"] ==
             "/projects/#{project.id}/transponders"
  end

  test "omits project action and resources when projects are disabled", %{
    user: user,
    membership: membership,
    project: project
  } do
    Application.put_env(:trifle, :projects_enabled, false)

    items = CommandPalette.items(user, membership)

    refute find_item(items, "action:projects")
    refute find_item(items, "project:#{project.id}")
  end

  defp find_item(items, id) do
    Enum.find(items, &(&1["id"] == id))
  end
end
