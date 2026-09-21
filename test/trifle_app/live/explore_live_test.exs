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
