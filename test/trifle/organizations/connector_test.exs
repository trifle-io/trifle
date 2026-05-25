defmodule Trifle.Organizations.ConnectorTest do
  use Trifle.DataCase, async: true

  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationConnector
  alias Trifle.Repo

  describe "organization connectors" do
    test "creates a connector with a one-time token" do
      organization = organization_fixture()

      assert {:ok, %OrganizationConnector{} = connector, token} =
               Organizations.create_connector_for_org(organization, %{name: "Private VPC"})

      assert connector.organization_id == organization.id
      assert connector.token_last5 == OrganizationConnector.token_last5(token)
      assert String.starts_with?(token, "trf_connector_")
      assert {:ok, %{connector: authenticated}} = Organizations.get_connector_auth(token)
      assert authenticated.id == connector.id
    end

    test "records heartbeat metadata" do
      {connector, _token} = organization_connector_with_token_fixture()

      assert {:ok, updated} =
               Organizations.record_connector_heartbeat(connector, %{
                 version: "1.2.3",
                 hostname: "connector-host",
                 capabilities: ["postgres", "redis"],
                 metadata: %{"runtime" => "docker"}
               })

      assert updated.status == "online"
      assert updated.version == "1.2.3"
      assert updated.hostname == "connector-host"
      assert updated.capabilities == ["postgres", "redis"]
      assert updated.metadata == %{"runtime" => "docker"}
      assert updated.last_heartbeat_at
      assert updated.last_seen_at
    end

    test "dispatches pending jobs once and records completion" do
      {connector, _token} = organization_connector_with_token_fixture()

      assert {:ok, job} =
               Organizations.enqueue_connector_job(connector, "tcp_check", %{
                 "host" => "db.internal",
                 "port" => 5432
               })

      assert [%{id: job_id, status: "running"}] =
               Organizations.list_pending_connector_jobs(connector)

      assert job_id == job.id
      assert [] = Organizations.list_pending_connector_jobs(connector)

      assert {:ok, completed} =
               Organizations.complete_connector_job(connector, job.id, %{
                 "status" => "ok",
                 "result" => %{"reachable" => true}
               })

      assert completed.status == "ok"
      assert completed.result == %{"reachable" => true}
      assert completed.completed_at
    end

    test "deleting a connector moves linked databases back to direct" do
      organization = organization_fixture()

      {connector, _token} =
        organization_connector_with_token_fixture(%{organization: organization})

      {:ok, database} =
        Organizations.create_database_for_org(organization, %{
          display_name: "Primary MySQL",
          driver: "mysql",
          host: "127.0.0.1",
          port: 3306,
          database_name: "trifle_stats",
          username: "trifle",
          password: "secret",
          connection_method: "connector",
          organization_connector_id: connector.id
        })

      assert {:ok, _deleted} = Organizations.delete_connector(connector)

      database = Repo.reload!(database)
      assert database.connection_method == "direct"
      assert database.organization_connector_id == nil
    end
  end
end
