defmodule Trifle.Organizations.ConnectorDatabaseCheckTest do
  use Trifle.DataCase, async: false

  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.ConnectorJob
  alias Trifle.Organizations.Database
  alias Trifle.Repo

  test "checks connector-connected database reachability through a connector job" do
    organization = organization_fixture()
    {connector, _token} = organization_connector_with_token_fixture(%{organization: organization})
    database = connector_database_fixture(organization, connector)

    task = Task.async(fn -> Database.check_status(database) end)

    job = wait_for_connector_job(connector.id)
    assert job.type == "database_tcp_check"
    assert job.payload["database_id"] == database.id
    assert job.payload["driver"] == "mongo"
    assert job.payload["host"] == "mongo.internal"
    assert job.payload["port"] == 27017

    assert {:ok, _completed} =
             Organizations.complete_connector_job(connector, job.id, %{
               "status" => "ok",
               "result" => %{"reachable" => true}
             })

    assert {:ok, updated_database, true} = Task.await(task, 2_000)
    assert updated_database.last_check_status == "success"
    assert updated_database.last_error == nil
  end

  test "records connector reachability failures" do
    organization = organization_fixture()
    {connector, _token} = organization_connector_with_token_fixture(%{organization: organization})
    database = connector_database_fixture(organization, connector)

    task = Task.async(fn -> Database.check_status(database) end)

    job = wait_for_connector_job(connector.id)

    assert {:ok, _completed} =
             Organizations.complete_connector_job(connector, job.id, %{
               "status" => "ok",
               "result" => %{"reachable" => false, "error" => "connection refused"}
             })

    assert {:error, updated_database, "connection refused"} = Task.await(task, 2_000)
    assert updated_database.last_check_status == "error"
    assert updated_database.last_error == "connection refused"
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
        organization_connector_id: connector.id
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
