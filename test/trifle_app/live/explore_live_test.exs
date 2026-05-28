defmodule TrifleApp.ExploreLiveTest do
  use TrifleApp.ConnCase

  import Phoenix.LiveViewTest
  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Organizations

  test "renders connector-backed databases in Explore", %{conn: conn} do
    {conn, database} = connector_database_conn(conn)

    assert {:ok, _view, html} =
             live_following_redirect(
               conn,
               ~p"/explore?source_type=database&source_id=#{database.id}"
             )

    assert html =~ "Private Mongo"
    refute html =~ "Source not available in Explore"
  end

  test "auto-selects connector-backed databases for Explore", %{conn: conn} do
    {conn, _database} = connector_database_conn(conn)

    assert {:ok, _view, html} = live_following_redirect(conn, ~p"/explore")

    assert html =~ "Private Mongo"
    refute html =~ "No sources available in Explore"
  end

  defp connector_database_conn(conn) do
    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    {connector, _token} = organization_connector_with_token_fixture(%{organization: organization})

    {:ok, database} =
      Organizations.create_database_for_org(organization, %{
        display_name: "Private Mongo",
        driver: "mongo",
        host: "mongo.internal",
        port: 27017,
        database_name: "trifle_stats",
        username: "trifle",
        password: "secret",
        connection_method: "connector",
        organization_connector_id: connector.id
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
