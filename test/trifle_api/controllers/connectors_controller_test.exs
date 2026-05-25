defmodule TrifleApi.ConnectorsControllerTest do
  use TrifleApp.ConnCase, async: true

  import Trifle.OrganizationsFixtures

  alias Trifle.Organizations
  alias Trifle.Repo

  setup %{conn: conn} do
    organization = organization_fixture()
    {connector, token} = organization_connector_with_token_fixture(%{organization: organization})

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"), connector: connector, token: token}
  end

  test "heartbeat updates the authenticated connector", %{
    conn: conn,
    connector: connector,
    token: token
  } do
    conn =
      conn
      |> auth_connector_conn(token)
      |> post(~p"/api/v1/connectors/heartbeat", %{
        "connector_id" => connector.id,
        "version" => "1.0.0",
        "hostname" => "connector-host",
        "capabilities" => ["postgres", "redis"],
        "metadata" => %{"runtime" => "docker"}
      })

    assert %{"data" => %{"connector" => %{"id" => connector_id, "status" => "online"}}} =
             json_response(conn, 200)

    assert connector_id == connector.id

    connector = Repo.reload!(connector)
    assert connector.version == "1.0.0"
    assert connector.hostname == "connector-host"
    assert connector.last_heartbeat_at
  end

  test "jobs endpoint returns pending jobs", %{conn: conn, connector: connector, token: token} do
    {:ok, job} =
      Organizations.enqueue_connector_job(connector, "ping", %{
        "message" => "hello"
      })

    conn =
      conn
      |> auth_connector_conn(token)
      |> get(~p"/api/v1/connectors/jobs?connector_id=#{connector.id}")

    assert %{
             "data" => %{
               "jobs" => [
                 %{"id" => job_id, "type" => "ping", "payload" => %{"message" => "hello"}}
               ]
             }
           } = json_response(conn, 200)

    assert job_id == job.id
  end

  test "job completion records result", %{conn: conn, connector: connector, token: token} do
    {:ok, job} = Organizations.enqueue_connector_job(connector, "ping", %{})

    conn =
      conn
      |> auth_connector_conn(token)
      |> post(~p"/api/v1/connectors/jobs/#{job.id}/complete", %{
        "status" => "ok",
        "result" => %{"pong" => true}
      })

    assert response(conn, 204)

    job = Repo.reload!(job)
    assert job.status == "ok"
    assert job.result == %{"pong" => true}
    assert job.completed_at
  end

  test "rejects missing bearer token", %{conn: conn} do
    conn = post(conn, ~p"/api/v1/connectors/heartbeat", %{})

    assert json_response(conn, 401)
  end

  defp auth_connector_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
