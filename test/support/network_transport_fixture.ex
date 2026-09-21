defmodule Trifle.NetworkTransportFixture do
  @moduledoc false
  # A real mTLS HTTP/stream endpoint. Tailscale itself is exercised separately
  # by the gateway's netmap/isolation tests; no customer tailnet is needed here.

  def start(target, owner) do
    dir =
      Path.join(System.tmp_dir!(), "trifle-network-test-#{System.unique_integer([:positive])}")

    {_, 0} =
      System.cmd("bash", [".devops/scripts/create-gateway-certs.sh", dir, "localhost"],
        stderr_to_stdout: true
      )

    cert = Path.join(dir, "server.crt")
    key = Path.join(dir, "server.key")
    ca = Path.join(dir, "ca.crt")

    {:ok, listener} =
      :ssl.listen(0, [
        :binary,
        ip: {127, 0, 0, 1},
        active: false,
        reuseaddr: true,
        certfile: String.to_charlist(cert),
        keyfile: String.to_charlist(key),
        cacertfile: String.to_charlist(ca),
        verify: :verify_peer,
        fail_if_no_peer_cert: true,
        versions: [:"tlsv1.3"]
      ])

    {:ok, {_, port}} = :ssl.sockname(listener)
    {:ok, workers} = Task.Supervisor.start_link()
    Process.unlink(workers)
    acceptor = spawn(fn -> accept(listener, workers, target, owner) end)
    previous = Application.get_env(:trifle, Trifle.Networking.Gateway)

    Application.put_env(:trifle, Trifle.Networking.Gateway,
      url: "https://localhost:#{port}",
      ca_file: ca,
      cert_file: Path.join(dir, "client.crt"),
      key_file: Path.join(dir, "client.key")
    )

    %{
      listener: listener,
      workers: workers,
      acceptor: acceptor,
      dir: dir,
      previous: previous,
      port: port
    }
  end

  def stop(fixture) do
    :ssl.close(fixture.listener)
    if Process.alive?(fixture.acceptor), do: Process.unlink(fixture.acceptor)
    Process.exit(fixture.acceptor, :shutdown)
    if Process.alive?(fixture.workers), do: Supervisor.stop(fixture.workers)
    File.rm_rf!(fixture.dir)

    if fixture.previous,
      do: Application.put_env(:trifle, Trifle.Networking.Gateway, fixture.previous),
      else: Application.delete_env(:trifle, Trifle.Networking.Gateway)
  end

  defp accept(listener, workers, target, owner) do
    case :ssl.transport_accept(listener) do
      {:ok, socket} ->
        {:ok, pid} =
          Task.Supervisor.start_child(workers, fn ->
            receive do
              {:socket, ^socket} ->
                try do
                  with {:ok, socket} <- :ssl.handshake(socket, 5_000),
                       do: handle(socket, target, owner)
                after
                  :ssl.close(socket)
                end
            end
          end)

        :ssl.controlling_process(socket, pid)
        send(pid, {:socket, socket})
        accept(listener, workers, target, owner)

      _ ->
        :ok
    end
  end

  defp handle(socket, target, owner) do
    :ssl.setopts(socket, packet: :http_bin)

    with {:ok, {:http_request, method, {:abs_path, path}, _}} <- :ssl.recv(socket, 0, 5_000),
         {:ok, headers} <- headers(socket, %{}),
         :ok <- :ssl.setopts(socket, packet: :raw),
         {:ok, body} <- :ssl.recv(socket, String.to_integer(headers["content-length"]), 5_000) do
      payload = Jason.decode!(body)
      send(owner, {:gateway_request, method, path, payload})

      case path do
        "/v1/streams" ->
          :ssl.send(
            socket,
            "HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: trifle-stream\r\n\r\n"
          )

          if is_function(target, 2) do
            target.(socket, payload)
          else
            {host, port} = target

            with {:ok, remote} <-
                   :gen_tcp.connect(
                     String.to_charlist(host),
                     port,
                     [:binary, active: false],
                     5_000
                   ) do
              try do
                :ssl.setopts(socket, active: :once)
                :inet.setopts(remote, active: :once)
                copy(socket, remote)
              after
                :gen_tcp.close(remote)
              end
            end
          end

        "/v1/status" ->
          reply(socket, %{
            state: "Running",
            enrolled: true,
            hostname: "trifle.test.ts.net",
            ips: ["100.64.0.7"]
          })

        _ ->
          reply(socket, %{accepted: true})
      end
    end
  end

  defp headers(socket, acc) do
    case :ssl.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, key, _, value}} ->
        headers(socket, Map.put(acc, key |> to_string() |> String.downcase(), value))

      {:ok, :http_eoh} ->
        {:ok, acc}

      other ->
        other
    end
  end

  defp reply(socket, payload) do
    body = Jason.encode!(payload)

    :ssl.send(socket, [
      "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: ",
      Integer.to_string(byte_size(body)),
      "\r\n\r\n",
      body
    ])
  end

  defp copy(socket, remote) do
    receive do
      {:ssl, ^socket, bytes} ->
        :gen_tcp.send(remote, bytes)
        :ssl.setopts(socket, active: :once)
        copy(socket, remote)

      {:tcp, ^remote, bytes} ->
        :ssl.send(socket, bytes)
        :inet.setopts(remote, active: :once)
        copy(socket, remote)

      _ ->
        :ok
    after
      15_000 -> :ok
    end
  end
end
