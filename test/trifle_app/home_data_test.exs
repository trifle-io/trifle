defmodule TrifleApp.HomeDataTest do
  use Trifle.DataCase, async: true

  import Trifle.AccountsFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Stats.Series
  alias TrifleApp.HomeData

  test "source_activity uses a bounded connector timeout and summarizes counts" do
    user = user_fixture()
    organization = organization_fixture(%{user: user})
    database_fixture(%{organization: organization, display_name: "Events"})
    membership = Organizations.get_membership_for_user(user)
    parent = self()
    at = DateTime.utc_now()

    fetcher = fn source, key, _from, _to, granularity, opts ->
      send(parent, {:fetch, source, key, granularity, opts})

      {:ok,
       %{
         series: %Series{
           series: %{at: [at], values: [%{"count" => 7}]}
         }
       }}
    end

    assert [%{total: 7.0, last_event_at: ^at}] =
             HomeData.source_activity(membership, fetcher: fetcher)

    assert_received {:fetch, _source, "__system__key__", "1h", opts}
    assert opts[:transponders] == :none
    assert opts[:connector_timeout] == 15_000
  end
end
