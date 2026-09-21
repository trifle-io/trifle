defmodule Trifle.Networking.Forwarder do
  @moduledoc "Supervised loopback TCP/SOCKS forwarding over the authenticated gateway."
  use GenServer, restart: :temporary
  alias Trifle.Organizations.NetworkConnections

  def start_link({route, mode}),
    do: GenServer.start_link(__MODULE__, {route, mode}, name: name(route))

  def endpoint(route, mode) do
    case DynamicSupervisor.start_child(
           Trifle.Networking.ForwarderSupervisor,
           {__MODULE__, {route, mode}}
         ) do
      {:ok, pid} ->
        GenServer.call(pid, {:endpoint, route})

      {:error, {:already_started, pid}} ->
        case GenServer.call(pid, {:endpoint, route}) do
          {:error, :stale_forwarder} ->
            DynamicSupervisor.terminate_child(Trifle.Networking.ForwarderSupervisor, pid)
            endpoint(route, mode)

          result ->
            result
        end

      error ->
        error
    end
  end

  def stop(database_id) do
    for kind <- ["database", "s3"],
        {pid, _} <- Registry.lookup(Trifle.Networking.ForwarderRegistry, {database_id, kind}) do
      DynamicSupervisor.terminate_child(Trifle.Networking.ForwarderSupervisor, pid)
    end

    :ok
  end

  defp name(route),
    do: {:via, Registry, {Trifle.Networking.ForwarderRegistry, {route.resource_id, route.kind}}}

  @impl true
  def init({route, mode}) do
    Process.flag(:trap_exit, true)
    Phoenix.PubSub.subscribe(Trifle.PubSub, "network:#{route.connection_id}")
    Phoenix.PubSub.subscribe(Trifle.PubSub, "network-source:#{route.resource_id}")

    with {:ok, listener} <-
           :gen_tcp.listen(0, [
             :binary,
             ip: {127, 0, 0, 1},
             active: false,
             reuseaddr: true,
             exit_on_close: false
           ]),
         {:ok, {_, port}} <- :inet.sockname(listener),
         {:ok, workers} <- Task.Supervisor.start_link() do
      acceptor = spawn_link(fn -> accept(listener, workers, route, mode) end)
      {:ok, %{listener: listener, port: port, workers: workers, acceptor: acceptor, route: route}}
    end
  end

  @impl true
  def handle_call({:endpoint, route}, _from, %{route: route} = state),
    do: {:reply, {:ok, state.port}, state}

  def handle_call({:endpoint, _route}, _from, state),
    do: {:reply, {:error, :stale_forwarder}, state}

  @impl true
  def handle_info(message, state) when message in [:network_changed, :source_changed] do
    for driver <- [:postgres, :mongo, :mysql, :redis],
        do: Trifle.DatabasePools.VersionRegistry.delete(driver, state.route.resource_id)

    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  @impl true
  def terminate(_reason, state) do
    :gen_tcp.close(state.listener)
    Process.exit(state.acceptor, :shutdown)
    if Process.alive?(state.workers), do: Supervisor.stop(state.workers)
    :ok
  end

  defp accept(listener, workers, route, mode) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, pid} =
          Task.Supervisor.start_child(workers, fn ->
            receive do
              {:socket, ^socket} -> serve(socket, route, mode)
            after
              5_000 -> :ok
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, pid)
        send(pid, {:socket, socket})
        accept(listener, workers, route, mode)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        exit(reason)
    end
  end

  defp serve(socket, route, mode) do
    try do
      with :ok <- handshake(socket, route, mode),
           {:ok, upstream} <- NetworkConnections.client().open_stream(route) do
        try do
          if mode == :socks5, do: :gen_tcp.send(socket, <<5, 0, 0, 1, 0, 0, 0, 0, 0, 0>>)
          :inet.setopts(socket, active: :once, send_timeout: 15_000, send_timeout_close: true)
          :ssl.setopts(upstream, active: :once, send_timeout: 15_000, send_timeout_close: true)
          relay(socket, upstream)
        after
          :ssl.close(upstream)
        end
      end
    after
      :gen_tcp.close(socket)
    end
  end

  defp handshake(_socket, _route, :tcp), do: :ok

  defp handshake(socket, route, :socks5) do
    with {:ok, <<5, count>>} <- :gen_tcp.recv(socket, 2, 5_000),
         {:ok, methods} <- :gen_tcp.recv(socket, count, 5_000),
         true <- 0 in :binary.bin_to_list(methods),
         :ok <- :gen_tcp.send(socket, <<5, 0>>),
         {:ok, <<5, 1, 0, type>>} <- :gen_tcp.recv(socket, 4, 5_000),
         {:ok, host} <- socks_host(socket, type),
         {:ok, <<port::16>>} <- :gen_tcp.recv(socket, 2, 5_000),
         true <- normalize_host(host) == normalize_host(route.host) and port == route.port do
      :ok
    else
      _ -> {:error, :destination_not_allowed}
    end
  end

  defp socks_host(socket, 3) do
    with {:ok, <<length>>} when length > 0 <- :gen_tcp.recv(socket, 1, 5_000),
         do: :gen_tcp.recv(socket, length, 5_000)
  end

  defp socks_host(socket, 1) do
    with {:ok, <<a, b, c, d>>} <- :gen_tcp.recv(socket, 4, 5_000),
         do: {:ok, Enum.join([a, b, c, d], ".")}
  end

  defp socks_host(socket, 4) do
    with {:ok, bytes} <- :gen_tcp.recv(socket, 16, 5_000) do
      address = for <<part::16 <- bytes>>, do: part
      {:ok, address |> List.to_tuple() |> :inet.ntoa() |> to_string()}
    end
  end

  defp socks_host(_, _), do: {:error, :invalid_address}

  defp normalize_host(host),
    do:
      host
      |> String.downcase()
      |> String.trim_trailing(".")
      |> String.trim_leading("[")
      |> String.trim_trailing("]")

  defp relay(socket, upstream) do
    receive do
      {:tcp, ^socket, bytes} ->
        with :ok <- :ssl.send(upstream, bytes),
             :ok <- :inet.setopts(socket, active: :once),
             do: relay(socket, upstream)

      {:ssl, ^upstream, bytes} ->
        with :ok <- :gen_tcp.send(socket, bytes),
             :ok <- :ssl.setopts(upstream, active: :once),
             do: relay(socket, upstream)

      {:tcp_closed, ^socket} ->
        :ssl.shutdown(upstream, :write)
        drain_upstream(socket, upstream)

      {:ssl_closed, ^upstream} ->
        :gen_tcp.shutdown(socket, :write)

      {:tcp_error, ^socket, _} ->
        :ok

      {:ssl_error, ^upstream, _} ->
        :ok
    after
      300_000 -> :ok
    end
  end

  defp drain_upstream(socket, upstream) do
    receive do
      {:ssl, ^upstream, bytes} ->
        with :ok <- :gen_tcp.send(socket, bytes),
             :ok <- :ssl.setopts(upstream, active: :once),
             do: drain_upstream(socket, upstream)

      _ ->
        :ok
    after
      30_000 -> :ok
    end
  end
end
