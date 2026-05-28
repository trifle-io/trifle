defmodule Trifle.Stats.ConnectorValuesTest do
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.ConnectorJob
  alias Trifle.Stats.Source
  alias Trifle.Repo

  test "fetches source series through a connector stats_values job" do
    organization = organization_fixture()
    {connector, _token} = organization_connector_with_token_fixture(%{organization: organization})
    database = connector_database_fixture(organization, connector)
    source = Source.from_database(database)
    from = ~U[2026-05-28 10:00:00Z]
    to = ~U[2026-05-28 11:00:00Z]

    task =
      Task.async(fn ->
        Source.fetch_series(source, "orders", from, to, "1h", connector_timeout: 2_000)
      end)

    job = wait_for_connector_job(connector.id)
    assert job.type == "stats_values"
    assert job.payload["driver"] == "mongo"
    assert job.payload["password"] == "secret"

    assert [%{"identifier" => %{"key" => first_key}}, %{"identifier" => %{"key" => second_key}}] =
             job.payload["points"]

    assert first_key == "orders::1h::1779962400"
    assert second_key == "orders::1h::1779966000"

    assert {:ok, _completed} =
             Organizations.complete_connector_job(connector, job.id, %{
               "status" => "ok",
               "result" => %{
                 "at" => [DateTime.to_iso8601(from), DateTime.to_iso8601(to)],
                 "values" => [%{"count" => 3}, %{"count" => 5}]
               }
             })

    assert {:ok, %{series: series, transponder_results: %{successful: []}}} =
             Task.await(task, 2_000)

    assert series.series[:at] == [from, to]
    assert series.series[:values] == [%{"count" => 3}, %{"count" => 5}]

    assert %ConnectorJob{payload: %{"password" => "[redacted]"}, result: %{"discarded" => true}} =
             Repo.reload!(job)
  end

  defp connector_database_fixture(organization, connector) do
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
        organization_connector_id: connector.id,
        granularities: ["1h", "1d"]
      })

    database
  end

  defp wait_for_connector_job(connector_id) do
    wait_for_connector_job(connector_id, System.monotonic_time(:millisecond) + 1_000)
  end

  defp wait_for_connector_job(connector_id, deadline) do
    case Repo.one(
           from j in ConnectorJob,
             where: j.organization_connector_id == ^connector_id,
             order_by: [desc: j.inserted_at],
             limit: 1
         ) do
      %ConnectorJob{} = job ->
        job

      nil ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("connector job was not enqueued")
        else
          Process.sleep(20)
          wait_for_connector_job(connector_id, deadline)
        end
    end
  end
end
