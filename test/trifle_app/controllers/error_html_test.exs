defmodule TrifleApp.ErrorHTMLTest do
  use TrifleApp.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations

  test "renders 404.html" do
    html = render_to_string(TrifleApp.ErrorHTML, "404", "html", [])

    assert html =~ "resource_lookup_failed()"
    assert html =~ "signed-in workspace members"
  end

  test "renders 500.html" do
    html = render_to_string(TrifleApp.ErrorHTML, "500", "html", [])

    assert html =~ "render_fault()"
    assert html =~ "Retry Request"
  end

  test "renders the styled 404 page for a private dashboard link", %{conn: conn} do
    owner = AccountsFixtures.user_fixture()
    viewer = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: owner})
    {:ok, _membership} = Organizations.create_membership(organization, viewer, "member")
    owner_membership = Organizations.get_membership_for_user(owner)
    database = database_fixture(%{organization: organization})

    {:ok, dashboard} =
      Organizations.create_dashboard_for_membership(owner, owner_membership, %{
        "name" => "Private Dashboard",
        "key" => "private-dashboard-#{System.unique_integer([:positive])}",
        "database_id" => database.id,
        "source_type" => "database",
        "source_id" => database.id,
        "default_timeframe" => "24h",
        "default_granularity" => "1m",
        "payload" => %{"grid" => []}
      })

    {status, _headers, body} =
      assert_error_sent :not_found, fn ->
        conn
        |> log_in_user(viewer)
        |> get(~p"/dashboards/#{dashboard.id}")
      end

    assert status == 404
    assert body =~ "resource_lookup_failed()"
    assert body =~ "signed-in workspace members"
  end
end
