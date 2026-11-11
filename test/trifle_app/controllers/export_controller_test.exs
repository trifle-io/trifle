defmodule TrifleApp.ExportControllerTest do
  use TrifleApp.ConnCase

  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations

  setup %{conn: conn} do
    owner = user_fixture()
    organization = organization_fixture(%{user: owner})
    app_entitlement_fixture(organization)
    membership = Organizations.get_membership_for_user(owner)
    database = database_fixture(%{organization: organization})

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(owner, membership, %{
        "name" => "Revenue",
        "key" => "revenue",
        "source_type" => "database",
        "source_id" => database.id
      })

    {:ok, conn: conn, owner: owner, dashboard: dashboard}
  end

  describe "dashboard exports are scoped to the caller's organization" do
    test "a member of another organization gets 404 for every format", %{
      conn: conn,
      dashboard: dashboard
    } do
      outsider = user_fixture()
      _other_org = organization_fixture(%{user: outsider, name: "Outsider Org"})
      conn = log_in_user(conn, outsider)

      for suffix <- [
            "json",
            "csv",
            "pdf",
            "png",
            "widgets/any-widget/pdf",
            "widgets/any-widget/png"
          ] do
        response = get(conn, "/export/dashboards/#{dashboard.id}/#{suffix}?key=anything")
        assert response.status == 404, "expected 404 for #{suffix}, got #{response.status}"
      end
    end

    test "a user without any organization gets 404", %{conn: conn, dashboard: dashboard} do
      conn = log_in_user(conn, user_fixture())

      assert get(conn, "/export/dashboards/#{dashboard.id}/json").status == 404
    end

    test "a malformed dashboard id is a 404, not a crash", %{conn: conn, owner: owner} do
      conn = log_in_user(conn, owner)

      assert get(conn, "/export/dashboards/not-a-uuid/json").status == 404
    end

    test "the owning organization is not blocked by the scope check", %{
      conn: conn,
      owner: owner,
      dashboard: dashboard
    } do
      conn = log_in_user(conn, owner)

      # The fixture database has no stats table, so the export itself may fail once
      # it reaches the source; what matters here is that it gets past the lookup.
      result =
        try do
          get(conn, "/export/dashboards/#{dashboard.id}/json").status
        rescue
          MatchError -> :reached_source
        end

      refute result == 404
    end

    test "anonymous requests are redirected to login", %{conn: conn, dashboard: dashboard} do
      conn = get(conn, "/export/dashboards/#{dashboard.id}/json")
      assert redirected_to(conn) == "/users/log_in"
    end
  end
end
