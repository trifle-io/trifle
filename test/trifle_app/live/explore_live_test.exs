defmodule TrifleApp.ExploreLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations

  test "renders Tailscale-backed databases in Explore", %{conn: conn} do
    {conn, database} = tailscale_database_conn(conn)

    assert {:ok, view, html} =
             live_following_redirect(
               conn,
               ~p"/explore?source_type=database&source_id=#{database.id}"
             )

    assert render_async(view) =~ "Private Mongo"
    assert html =~ "Private Mongo"
    refute html =~ "Source not available in Explore"
  end

  test "auto-selects Tailscale-backed databases for Explore", %{conn: conn} do
    {conn, _database} = tailscale_database_conn(conn)

    assert {:ok, view, html} = live_following_redirect(conn, ~p"/explore")

    assert render_async(view) =~ "Private Mongo"
    assert html =~ "Private Mongo"
    refute html =~ "No sources available in Explore"
  end

  test "expanded charts stay below the FilterBar while granularity changes", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    database = database_fixture(%{organization: organization})
    {:ok, _} = Organizations.setup_database(database)

    {:ok, view, _html} =
      live(
        log_in_user(conn, user),
        ~p"/explore?source_type=database&source_id=#{database.id}&timeframe=24h&granularity=1h"
      )

    render_async(view)
    render_click(view, "expand_widget", %{"id" => "explore-activity"})
    assert has_element?(view, "#explore-filter-bar-shortcuts ~ section#explore-expanded-widget")
    assert has_element?(view, "#explore-widgets[inert] #dashboard-grid")
    assert has_element?(view, "#explore-expanded-widget", "Activity")

    view |> element(~s([data-filter-bar-granularity="1d"])) |> render_click()
    assert assert_patch(view) =~ "granularity=1d"
    render_async(view)
    assert has_element?(view, "#explore-expanded-widget", "Activity")

    view |> element("#explore-expanded-widget [data-workspace-close]") |> render_click()
    refute has_element?(view, "#explore-expanded-widget")
    refute has_element?(view, "#explore-widgets[inert]")
  end

  defp tailscale_database_conn(conn) do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    connection = network_connection_fixture(%{organization: organization})

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "Private Mongo",
        driver: "mongo",
        host: "mongo.internal",
        port: 27017,
        database_name: "trifle_stats",
        username: "trifle",
        password: "secret",
        connection_method: "tailscale",
        network_connection_id: connection.id
      })

    {log_in_user(conn, user), database}
  end

  defp live_following_redirect(conn, path) do
    case live(conn, path) do
      {:error, {:live_redirect, %{to: to}}} -> live(conn, to)
      result -> result
    end
  end
end
