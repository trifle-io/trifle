defmodule Trifle.Organizations.NetworkConnectionsTest do
  use Trifle.DataCase, async: false
  import Trifle.OrganizationsFixtures
  alias Trifle.Organizations.{NetworkConnection, NetworkConnections}

  setup do
    Application.put_env(:trifle, :network_gateway_client, Trifle.NetworkGatewayStub)
    Application.put_env(:trifle, :gateway_stub_owner, self())

    on_exit(fn ->
      for key <- [
            :network_gateway_client,
            :gateway_stub_owner,
            :gateway_stub_status,
            :gateway_stub_configure
          ],
          do: Application.delete_env(:trifle, key)
    end)

    :ok
  end

  test "enrollment credentials are encrypted, hidden from lists, and cleared after enrollment" do
    connection = network_connection_fixture()
    assert [%{auth_key: nil}] = NetworkConnections.list(connection.organization_id)

    assert %{rows: [[encrypted]]} =
             Repo.query!("SELECT auth_key FROM organization_network_connections WHERE id = $1", [
               Ecto.UUID.dump!(connection.id)
             ])

    refute encrypted =~ "tskey-auth-"
    assert {:ok, updated} = NetworkConnections.refresh(connection)
    assert updated.status == "online"
    assert updated.auth_key == nil
    assert updated.addresses == ["100.64.0.5"]
    assert_receive {:configure, %{auth_key: "tskey-auth-test-key"}}
  end

  test "pending approval retains the enrollment key until a durable node is running" do
    Application.put_env(:trifle, :gateway_stub_status, %{
      "state" => "NeedsMachineAuth",
      "enrolled" => true
    })

    assert {:ok, updated} = network_connection_fixture() |> NetworkConnections.refresh()
    assert updated.status == "approval_required"
    assert updated.auth_key != nil
  end

  test "API tokens are rejected with auth-key guidance" do
    assert {:error, changeset} =
             NetworkConnections.create(organization_fixture(), %{
               name: "Production",
               auth_key: "tskey-api-not-an-auth-key"
             })

    assert errors_on(changeset).auth_key == [
             "must be a Tailscale auth key (tskey-auth-), not an API access token"
           ]
  end

  test "HTTP and LiveView parameter logging redact enrollment keys" do
    params = %{"connection" => %{"name" => "Production", "auth_key" => "tskey-auth-secret"}}
    assert Phoenix.Logger.filter_values(params)["connection"]["auth_key"] == "[FILTERED]"

    assert Phoenix.Logger.filter_values(%{"auth_key" => "tskey-auth-replacement"})["auth_key"] ==
             "[FILTERED]"
  end

  test "blank names and enrollment keys produce invalid changesets without raising" do
    connection = network_connection_fixture()

    for blank <- [nil, "", "   "] do
      changeset = NetworkConnection.changeset(connection, %{name: blank})
      assert errors_on(changeset).name == ["can't be blank"]

      assert {:error, changeset} = NetworkConnections.reauthorize(connection, blank)
      assert errors_on(changeset).auth_key == ["can't be blank"]
      assert Repo.reload!(connection).generation == 1
    end
  end

  test "refresh makes both gateway requests outside database transactions" do
    Application.put_env(:trifle, :gateway_stub_configure, fn _connection ->
      refute Repo.in_transaction?()
      {:ok, %{}}
    end)

    Application.put_env(:trifle, :gateway_stub_status, fn _connection ->
      refute Repo.in_transaction?()
      {:ok, %{"state" => "Running", "enrolled" => true}}
    end)

    assert {:ok, %{status: "online"}} = NetworkConnections.refresh(network_connection_fixture())
  end

  for operation <- [:reauthorize, :disconnect, :delete] do
    @tag operation: operation
    test "a late refresh cannot overwrite #{operation}", %{operation: operation} do
      connection = network_connection_fixture()
      owner = self()

      Application.put_env(:trifle, :gateway_stub_status, fn _connection ->
        send(owner, {:status_waiting, self()})

        receive do
          :finish_status -> {:ok, %{"state" => "Running", "enrolled" => true}}
        after
          5_000 -> {:error, :test_timeout}
        end
      end)

      refresh = Task.async(fn -> NetworkConnections.refresh(connection) end)
      assert_receive {:status_waiting, gateway_caller}

      result =
        case operation do
          :reauthorize -> NetworkConnections.reauthorize(connection, "tskey-auth-new-key")
          :disconnect -> NetworkConnections.disconnect(connection)
          :delete -> NetworkConnections.delete(connection)
        end

      assert {:ok, updated} = result
      send(gateway_caller, :finish_status)

      if operation == :delete do
        assert {:error, :network_connection_unavailable} = Task.await(refresh)
      else
        assert {:ok, ^updated} = Task.await(refresh)
        assert Repo.reload!(connection) == updated
      end
    end
  end

  test "a late gateway error cannot overwrite a new enrollment" do
    connection = network_connection_fixture()
    owner = self()

    Application.put_env(:trifle, :gateway_stub_configure, fn _connection ->
      send(owner, {:configure_waiting, self()})

      receive do
        :finish_configure -> {:error, :gateway_unavailable}
      after
        5_000 -> {:error, :test_timeout}
      end
    end)

    refresh = Task.async(fn -> NetworkConnections.refresh(connection) end)
    assert_receive {:configure_waiting, gateway_caller}
    assert {:ok, updated} = NetworkConnections.reauthorize(connection, "tskey-auth-new-key")
    send(gateway_caller, :finish_configure)
    assert {:ok, ^updated} = Task.await(refresh)
    assert Repo.reload!(connection).last_error == nil
  end

  test "organization lookup cannot reach another organization's connection" do
    connection = network_connection_fixture()

    assert NetworkConnections.get(
             organization_fixture(%{name: "Another organization"}).id,
             connection.id
           ) == nil

    assert NetworkConnections.get(connection.organization_id, "../escape") == nil
  end

  test "disconnect invalidates the gateway before reporting success" do
    connection = network_connection_fixture()
    assert {:ok, updated} = NetworkConnections.disconnect(connection)
    refute updated.enabled
    assert updated.generation == 2
    assert updated.auth_key == nil
    assert_receive {:configure, %{enabled: false, generation: 2, auth_key: nil}}

    assert {:error, :network_connection_unavailable} =
             NetworkConnections.available(connection.organization_id, connection.id)
  end

  test "gateway failure does not report a successful disconnect" do
    connection = network_connection_fixture()
    Application.put_env(:trifle, :gateway_stub_configure, {:error, :gateway_unavailable})
    assert {:error, :gateway_unavailable} = NetworkConnections.disconnect(connection)
    assert Repo.reload!(connection).enabled
  end

  test "reauthorization advances generation and stale callers refresh current state" do
    connection = network_connection_fixture()
    assert {:ok, updated} = NetworkConnections.reauthorize(connection, "tskey-auth-new-key")
    assert updated.generation == 2
    assert {:ok, _} = NetworkConnections.refresh(connection)
    assert_receive {:configure, %{generation: 2, auth_key: "tskey-auth-new-key"}}
  end

  test "connections used by payload storage cannot be deleted" do
    organization = organization_fixture()
    connection = network_connection_fixture(%{organization: organization})
    database = database_fixture(%{organization: organization})

    database
    |> Ecto.Changeset.change(trace_network_connection_id: connection.id)
    |> Repo.update!()

    assert {:error, :connection_in_use} = NetworkConnections.delete(connection)
    assert Repo.get(NetworkConnection, connection.id)
    refute_receive {:configure, _}
  end

  test "deleting an unused connection disables its gateway identity" do
    connection = network_connection_fixture()
    assert {:ok, _} = NetworkConnections.delete(connection)
    assert_receive {:configure, %{enabled: false, generation: 2}}
    assert Repo.get(NetworkConnection, connection.id) == nil
  end

  test "background refresh uses identifiers only and clears enrolled credentials without a browser" do
    connection = network_connection_fixture()
    worker = Trifle.Networking.RefreshConnections

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = worker.perform(%Oban.Job{args: %{}})
    end)

    [job] =
      Repo.all(from j in Oban.Job, where: j.worker == "Trifle.Networking.RefreshConnections")

    assert job.args == %{"organization_id" => connection.organization_id, "id" => connection.id}
    assert :ok = worker.perform(job)
    assert Repo.reload!(connection).auth_key == nil
  end
end
