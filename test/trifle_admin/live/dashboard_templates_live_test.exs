defmodule TrifleAdmin.DashboardTemplatesLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Accounts
  alias Trifle.AccountsFixtures
  alias Trifle.Organizations

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, user} = Accounts.update_user_admin_status(user.id, true)
    organization = organization_fixture(%{user: user})
    membership = Organizations.get_membership_for_user(user)
    app_entitlement_fixture(organization)

    {:ok, template} =
      Organizations.create_dashboard_template(user, membership, %{
        name: "Operations overview",
        payload: %{"grid" => [%{"id" => "throughput"}]}
      })

    {:ok,
     conn: log_in_user(conn, user),
     user: user,
     organization: organization,
     membership: membership,
     template: template}
  end

  test "lists database-backed templates without system templates", %{
    conn: conn,
    organization: organization,
    template: template
  } do
    {:ok, _view, html} = live(conn, "/admin/dashboard-templates")

    assert html =~ template.name
    assert html =~ organization.name
    assert html =~ "user:#{template.id}"
    refute html =~ "Blank dashboard"
  end

  test "shows template details and linked dashboard usage", context do
    database = database_fixture(%{organization: context.organization})

    {:ok, _dashboard} =
      Organizations.create_dashboard_for_membership(context.user, context.membership, %{
        name: "Linked dashboard",
        key: "linked.#{System.unique_integer([:positive])}",
        source_type: "database",
        source_id: database.id,
        database_id: database.id,
        template_id: "user:#{context.template.id}"
      })

    {:ok, _view, html} =
      live(context.conn, "/admin/dashboard-templates/#{context.template.id}/show")

    assert html =~ "Dashboard Template Details"
    assert html =~ "Linked dashboards"
    assert html =~ "throughput"
  end

  test "rejects non-administrators before index or show renders", context do
    user = AccountsFixtures.user_fixture()
    conn = log_in_user(build_conn(), user)

    for path <- [
          "/admin/dashboard-templates",
          "/admin/dashboard-templates/#{context.template.id}/show"
        ] do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path)
      assert flash["error"] == "Administrator access is required."
    end
  end
end
