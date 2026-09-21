defmodule Trifle.Networking.TailscaleTransportTest do
  use Trifle.DataCase, async: false
  import Trifle.OrganizationsFixtures
  alias Trifle.Networking.{DatabaseEndpoint, Forwarder, Gateway, Tailscale}
  alias Trifle.Organizations.{Database, NetworkConnections}

  test "Stats queries and trace index operations use the gateway through production adapters" do
    repo = Repo.config()
    fixture = Trifle.NetworkTransportFixture.start({repo[:hostname], repo[:port] || 5432}, self())
    on_exit(fn -> Trifle.NetworkTransportFixture.stop(fixture) end)
    org = organization_fixture()
    connection = network_connection_fixture(%{organization: org})
    suffix = System.unique_integer([:positive])
    stats_table = "network_stats_#{suffix}"
    trace_table = "network_traces_#{suffix}"
    trace_path = Path.join(System.tmp_dir!(), "network-traces-#{suffix}")

    {:ok, database} =
      Trifle.Organizations.create_database_for_org(org, %{
        display_name: "Private traces",
        driver: "postgres",
        host: "100.64.0.7",
        port: 5432,
        username: repo[:username],
        password: repo[:password],
        database_name: repo[:database],
        connection_method: "tailscale",
        network_connection_id: connection.id,
        granularities: ["1m"],
        config: %{"table_name" => stats_table, "pool_size" => 1},
        trace_config: %{
          "index_name" => trace_table,
          "data_driver" => "file",
          "data_path" => trace_path,
          "retention_days" => 7,
          "gzip" => true
        }
      })

    try do
      assert {:ok, _} = Database.setup(database)
      assert {:ok, _, true} = Database.check_status(database)
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      config = Database.connected_stats_config(database)

      Trifle.Stats.track("jobs/NetworkTest", now, %{count: 2}, %{
        config
        | storage: nil,
          buffer_enabled: false
      })

      assert {:ok, %{series: series}} =
               Trifle.Stats.SeriesFetcher.fetch_series(
                 database,
                 "jobs/NetworkTest",
                 DateTime.add(now, -60),
                 DateTime.add(now, 60),
                 "1m",
                 []
               )

      assert Enum.any?(series.series.values, &(&1["count"] == 2))

      trace_config = Trifle.Traces.Source.Database.configuration(database)

      record = %Trifle.Traces.TraceRecord{
        reference: "network-test",
        key: "jobs/NetworkTest",
        first_at: now,
        last_at: now,
        expires_at: DateTime.add(now, 3600),
        state: :success
      }

      Trifle.Traces.Driver.Index.Postgres.create(trace_config.index_driver, record)

      assert %{reference: "network-test", state: :success} =
               Trifle.Traces.Driver.Index.Postgres.find(trace_config.index_driver, "network-test")

      assert %{traces: [%{reference: "network-test"}]} =
               Trifle.Traces.Driver.Index.Postgres.search(trace_config.index_driver, [])

      assert_received {:gateway_request, :POST, "/v1/streams", %{"host" => "100.64.0.7"}}
    after
      Trifle.DatabasePools.PoolManager.stop_all_pools_for_database(database.id)

      for table <- [trace_table, stats_table, stats_table <> "_ping"],
          do: Repo.query!("DROP TABLE IF EXISTS #{table}")

      File.rm_rf!(trace_path)
    end
  end

  test "PostgreSQL queries travel through the real mTLS upgrade and loopback forwarder" do
    repo = Repo.config()
    fixture = Trifle.NetworkTransportFixture.start({repo[:hostname], repo[:port] || 5432}, self())
    on_exit(fn -> Trifle.NetworkTransportFixture.stop(fixture) end)
    org = organization_fixture()
    connection = network_connection_fixture(%{organization: org})
    {:ok, connection} = NetworkConnections.refresh(connection)
    assert connection.auth_key == nil

    database = %Database{
      id: Ecto.UUID.generate(),
      organization_id: org.id,
      network_connection_id: connection.id,
      connection_method: "tailscale",
      driver: "postgres",
      host: "100.64.0.7",
      port: 5432,
      pool_version: 1
    }

    on_exit(fn -> Forwarder.stop(database.id) end)
    assert {:ok, %{host: "127.0.0.1", port: port}} = DatabaseEndpoint.resolve(database)

    {:ok, db} =
      Postgrex.start_link(
        hostname: "127.0.0.1",
        port: port,
        username: repo[:username],
        password: repo[:password],
        database: repo[:database]
      )

    assert %{rows: [[42]]} = Postgrex.query!(db, "SELECT 42", [])
    GenServer.stop(db)

    assert_received {:gateway_request, :POST, "/v1/streams",
                     %{"organization_id" => org_id, "host" => "100.64.0.7", "port" => 5432}}

    assert org_id == org.id
  end

  test "disconnect closes an active database stream without restarting its old route" do
    repo = Repo.config()
    fixture = Trifle.NetworkTransportFixture.start({repo[:hostname], repo[:port] || 5432}, self())
    on_exit(fn -> Trifle.NetworkTransportFixture.stop(fixture) end)
    connection = network_connection_fixture()

    database = %Database{
      id: Ecto.UUID.generate(),
      organization_id: connection.organization_id,
      network_connection_id: connection.id,
      connection_method: "tailscale",
      driver: "postgres",
      host: "100.64.0.7",
      port: 5432,
      pool_version: 1
    }

    on_exit(fn -> Forwarder.stop(database.id) end)
    assert {:ok, %{port: port}} = DatabaseEndpoint.resolve(database)
    [{pid, _}] = Registry.lookup(Trifle.Networking.ForwarderRegistry, {database.id, "database"})
    monitor = Process.monitor(pid)
    assert {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    assert_receive {:gateway_request, :POST, "/v1/streams", _}
    assert {:ok, _} = NetworkConnections.disconnect(connection)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)
    # Registry removes dead entries asynchronously after the process exits.
    for {registered, _} <-
          Registry.lookup(Trifle.Networking.ForwarderRegistry, {database.id, "database"}),
        do: refute(Process.alive?(registered))

    assert {:error, :network_connection_unavailable} = DatabaseEndpoint.resolve(database)
  end

  test "gateway certificates must match the configured hostname" do
    fixture = Trifle.NetworkTransportFixture.start(fn _, _ -> :ok end, self())
    on_exit(fn -> Trifle.NetworkTransportFixture.stop(fixture) end)
    config = Application.fetch_env!(:trifle, Gateway)

    Application.put_env(
      :trifle,
      Gateway,
      Keyword.put(config, :url, "https://127.0.0.1:#{fixture.port}")
    )

    assert {:error, :gateway_unavailable} = Gateway.configure(network_connection_fixture())
    assert {:error, :gateway_unavailable} = Gateway.open_stream(%{})
    refute_received {:gateway_request, _, _, _}
  end

  test "private S3 preserves the signed destination and bypasses host DNS and shared pools" do
    owner = self()

    upstream = fn socket, _route ->
      :ssl.setopts(socket, packet: :http_bin)
      {:ok, {:http_request, method, path, _}} = :ssl.recv(socket, 0, 5_000)
      headers = read_headers(socket, %{})
      send(owner, {:s3_request, method, path, headers})
      :ssl.setopts(socket, packet: :raw)
      :ssl.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\ntrace")
    end

    fixture = Trifle.NetworkTransportFixture.start(upstream, self())
    on_exit(fn -> Trifle.NetworkTransportFixture.stop(fixture) end)
    org = organization_fixture()
    connection = network_connection_fixture(%{organization: org})

    database = %Database{
      id: Ecto.UUID.generate(),
      organization_id: org.id,
      trace_network_connection_id: connection.id,
      pool_version: 1,
      trace_config: %{"data_endpoint" => "http://minio.private.ts.net:9000"}
    }

    on_exit(fn -> Forwarder.stop(database.id) end)
    assert {:ok, options} = Tailscale.s3_options(database)
    assert options[:pool] == false

    config = [
      scheme: "http://",
      host: "minio.private.ts.net",
      port: 9000,
      region: "us-east-1",
      access_key_id: "test-access",
      secret_access_key: "test-secret",
      http_opts: options
    ]

    assert {:ok, %{body: "trace"}} =
             ExAws.S3.get_object("bucket", "part.gz") |> ExAws.request(config)

    assert_receive {:s3_request, :GET, _, headers}
    assert headers["host"] == "minio.private.ts.net:9000"
    assert headers["authorization"] =~ "AWS4-HMAC-SHA256"
    assert headers["authorization"] =~ "Credential=test-access/"
  end

  test "missing gateway configuration and foreign connection IDs fail closed" do
    org = organization_fixture()
    connection = network_connection_fixture(%{organization: org})
    other = organization_fixture(%{name: "Different organization"})

    db = %Database{
      id: Ecto.UUID.generate(),
      organization_id: other.id,
      network_connection_id: connection.id,
      connection_method: "tailscale",
      driver: "postgres",
      host: "100.64.0.7",
      port: 5432
    }

    assert {:error, :network_connection_unavailable} = DatabaseEndpoint.resolve(db)
    assert {:error, :gateway_not_configured} = Gateway.transport_options()
  end

  defp read_headers(socket, acc) do
    case :ssl.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, key, _, value}} ->
        read_headers(socket, Map.put(acc, key |> to_string() |> String.downcase(), value))

      {:ok, :http_eoh} ->
        acc
    end
  end
end
