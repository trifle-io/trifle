defmodule Trifle.Networking.RefreshConnectionsTest do
  use Trifle.DataCase, async: false
  use Oban.Testing, repo: Trifle.Repo

  import Trifle.OrganizationsFixtures

  alias Trifle.Networking.RefreshConnections
  alias Trifle.Organizations.NetworkConnections
  alias Trifle.Traces
  alias Trifle.Traces.Configuration

  setup do
    keys = [
      :network_gateway_client,
      :gateway_stub_owner,
      :gateway_stub_status,
      :gateway_stub_configure
    ]

    previous = Map.new(keys, &{&1, Application.fetch_env(:trifle, &1)})

    Application.put_env(:trifle, :network_gateway_client, Trifle.NetworkGatewayStub)
    Application.put_env(:trifle, :gateway_stub_owner, self())

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:trifle, key, value)
          :error -> Application.delete_env(:trifle, key)
        end
      end
    end)

    owner = self()

    config =
      Configuration.new(
        index_driver: Traces.Driver.Index.Memory.new(),
        data_driver: Traces.Driver.Data.Memory.new(),
        on_wrapup: &send(owner, {:trace, &1})
      )

    # Exercise the real Oban Telemetry lifecycle, as configured in Observability.
    handler_id = {__MODULE__, self()}
    start_supervised!({Traces.Oban, config: config, handler_id: handler_id})
    on_exit(fn -> :telemetry.detach(handler_id) end)
    %{config: config}
  end

  test "dispatch traces enabled connections, identifier-only jobs and duplicate skips", %{
    config: config
  } do
    organization = organization_fixture()
    connection = network_connection_fixture(%{organization: organization})

    disabled =
      network_connection_fixture(%{organization: organization})
      |> change(enabled: false)
      |> Repo.update!()

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert :ok = perform_job(RefreshConnections, %{})
      trace = assert_trace(config, %{})
      assert trace.state == :success
      assert_message(trace, "Dispatch network connection refreshes")
      assert_message(trace, "Enabled network connections: 1")
      assert_message(trace, "Network connection 1 of 1")
      assert_message(trace, "Enqueued: 1; already queued: 0")
      assert "network-connection:#{connection.id}" in trace.tags
      refute "network-connection:#{disabled.id}" in trace.tags
      [job] = all_enqueued(worker: RefreshConnections)
      assert job.args == args(connection)

      assert :ok = perform_job(RefreshConnections, %{})
      duplicate = assert_trace(config, %{})
      assert_message(duplicate, "Refresh job already queued; skipping duplicate")
      assert_message(duplicate, "Enqueued: 0; already queued: 1")
      assert length(all_enqueued(worker: RefreshConnections)) == 1
    end)
  end

  test "an empty dispatch still persists a useful trace", %{config: config} do
    assert :ok = perform_job(RefreshConnections, %{})
    trace = assert_trace(config, %{})
    assert_message(trace, "Enabled network connections: 0")
    assert_message(trace, "Enqueued: 0; already queued: 0")
  end

  test "refresh persists gateway steps and resource tags without enrollment credentials", %{
    config: config
  } do
    connection = network_connection_fixture()
    assert :ok = perform_job(RefreshConnections, args(connection))
    trace = assert_trace(config, args(connection))

    assert trace.state == :success
    assert "organization:#{connection.organization_id}" in trace.tags
    assert "network-connection:#{connection.id}" in trace.tags
    assert_message(trace, "Configure gateway connection")
    assert_message(trace, "Gateway configure succeeded")
    assert_message(trace, "Read gateway connection status")
    assert_message(trace, "Gateway status succeeded")
    assert_message(trace, "Gateway status: online; enrolled: true; clear stored auth key: true")
    assert_message(trace, "Network connection refresh saved; status: online")
    assert Repo.reload!(connection).auth_key == nil
    refute trace_text(trace) =~ connection.auth_key
    refute trace_text(trace) =~ "trifle.test.ts.net"
    refute trace_text(trace) =~ "100.64.0.5"
  end

  test "missing and disabled connections explain why no gateway refresh ran", %{config: config} do
    connection = network_connection_fixture() |> change(enabled: false) |> Repo.update!()
    assert :ok = perform_job(RefreshConnections, args(connection))
    trace = assert_trace(config, args(connection))
    assert_message(trace, "Network connection is disabled; skipping refresh")

    Repo.delete!(connection)
    assert :ok = perform_job(RefreshConnections, args(connection))
    trace = assert_trace(config, args(connection))
    assert trace.state == :warning
    assert_message(trace, "Network connection no longer exists; skipping refresh")
    refute_receive {:configure, _}
  end

  test "pending enrollment is a warning and does not expose the retained credential", %{
    config: config
  } do
    Application.put_env(:trifle, :gateway_stub_status, %{
      "state" => "NeedsMachineAuth",
      "enrolled" => true
    })

    connection = network_connection_fixture()
    assert :ok = perform_job(RefreshConnections, args(connection))
    trace = assert_trace(config, args(connection))

    assert trace.state == :warning

    assert_message(
      trace,
      "Gateway status: approval_required; enrolled: true; clear stored auth key: false"
    )

    assert_message(trace, "Network connection refresh saved; status: approval_required")
    assert Repo.reload!(connection).auth_key == connection.auth_key
    refute trace_text(trace) =~ connection.auth_key
  end

  for operation <- [:configure, :status] do
    @tag operation: operation
    test "gateway #{operation} failures mark the trace failed even when the job returns ok", %{
      config: config,
      operation: operation
    } do
      failure = {:error, {:transport, "private-gateway-response"}}
      Application.put_env(:trifle, :gateway_stub_configure, {:ok, %{}})

      if operation == :configure do
        Application.put_env(:trifle, :gateway_stub_configure, failure)
      else
        Application.put_env(:trifle, :gateway_stub_status, fn _ -> failure end)
      end

      connection = network_connection_fixture()
      assert :ok = perform_job(RefreshConnections, args(connection))
      trace = assert_trace(config, args(connection))

      assert trace.state == :error

      assert_message(
        trace,
        "Gateway #{operation} failed: #{NetworkConnections.error_message(:gateway_unavailable)}"
      )

      assert_message(trace, "Network connection refresh saved; status: error")
      assert Repo.reload!(connection).status == "error"
      refute trace_text(trace) =~ "private-gateway-response"
      refute trace_text(trace) =~ connection.auth_key
    end
  end

  test "a superseded refresh records why it kept the newer configuration", %{config: config} do
    connection = network_connection_fixture()

    Application.put_env(:trifle, :gateway_stub_status, fn current ->
      assert {:ok, _} = NetworkConnections.reauthorize(current, "tskey-auth-replacement")
      {:ok, %{"state" => "Running", "enrolled" => true}}
    end)

    assert :ok = perform_job(RefreshConnections, args(connection))
    trace = assert_trace(config, args(connection))
    assert trace.state == :warning
    assert_message(trace, "Connection generation changed; keeping newer configuration")
    assert_message(trace, "Network connection refresh saved; status: pending")
    assert Repo.reload!(connection).generation == 2
    refute trace_text(trace) =~ "tskey-auth-replacement"
  end

  test "a connection removed during refresh traces the existing retryable failure", %{
    config: config
  } do
    connection = network_connection_fixture()

    Application.put_env(:trifle, :gateway_stub_status, fn current ->
      Repo.delete!(current)
      {:ok, %{"state" => "Running", "enrolled" => true}}
    end)

    assert {:error, :gateway_unavailable} = perform_job(RefreshConnections, args(connection))
    trace = assert_trace(config, args(connection))
    assert trace.state == :error
    assert_message(trace, "Network connection refresh could not be saved")
  end

  defp args(connection),
    do: %{"organization_id" => connection.organization_id, "id" => connection.id}

  defp assert_trace(config, args) do
    assert_receive {:trace, %{key: "jobs/Trifle.Networking.RefreshConnections"} = trace}
    assert trace.meta == args
    assert Traces.current_tracer() == nil
    record = Traces.find(trace.reference, config: config)
    assert record.state == trace.state
    assert record.meta == args
    assert record.tags == trace.tags |> Enum.uniq() |> Enum.sort()
    assert record.context.worker == "Trifle.Networking.RefreshConnections"
    refute_receive {:trace, %{key: "jobs/Trifle.Networking.RefreshConnections"}}
    %{trace | data: Traces.payload(record, config: config)}
  end

  defp assert_message(trace, message) do
    assert Enum.any?(trace.data, &(&1.message == message)),
           "expected trace message #{inspect(message)}, got: #{trace_text(trace)}"
  end

  defp trace_text(trace), do: Enum.map_join(trace.data, "\n", & &1.message)
end
