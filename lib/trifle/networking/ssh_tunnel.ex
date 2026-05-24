defmodule Trifle.Networking.SSHTunnel do
  @moduledoc """
  Runtime process for a single SSH local-forward tunnel.

  The process owns the SSH connection, a loopback listener created through the
  Erlang/OTP SSH application, and a temporary private-key file used by the SSH
  client implementation.
  """

  use GenServer

  require Logger

  alias Trifle.Organizations.Database

  @connect_timeout 15_000

  defstruct [
    :database_id,
    :ssh_connection,
    :ssh_monitor,
    :local_port,
    :key_dir
  ]

  def child_spec(%Database{} = database) do
    %{
      id: {__MODULE__, database.id},
      start: {__MODULE__, :start_link, [database]},
      restart: :transient
    }
  end

  def start_link(%Database{} = database) do
    GenServer.start_link(__MODULE__, database, name: name(database.id))
  end

  def name(database_id) when is_binary(database_id), do: :"trifle_ssh_tunnel_#{database_id}"

  def endpoint(pid_or_name) do
    GenServer.call(pid_or_name, :endpoint)
  end

  @impl true
  def init(%Database{} = database) do
    Process.flag(:trap_exit, true)

    case open_tunnel(database) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:endpoint, _from, %__MODULE__{local_port: local_port} = state) do
    {:reply, {:ok, %{host: "127.0.0.1", port: local_port}}, state}
  end

  @impl true
  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, reason},
        %__MODULE__{ssh_monitor: monitor_ref} = state
      ) do
    Logger.warning("SSH tunnel for database #{state.database_id} closed: #{inspect(reason)}")
    {:stop, {:ssh_connection_closed, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %__MODULE__{} = state) do
    close_ssh(state.ssh_connection)
    cleanup_key_dir(state.key_dir)
    :ok
  end

  defp open_tunnel(%Database{connection_method: "ssh_tunnel"} = database) do
    with :ok <- ensure_tunnel_fields(database),
         :ok <- ssh_start(),
         {:ok, key_dir} <- prepare_key_dir(database) do
      open_tunnel_with_key_dir(database, key_dir)
    else
      {:error, reason} ->
        {:error, reason}

      reason ->
        {:error, reason}
    end
  end

  defp open_tunnel(%Database{}), do: {:error, :ssh_tunnel_not_configured}

  defp open_tunnel_with_key_dir(database, key_dir) do
    case connect_ssh(database, key_dir) do
      {:ok, connection} ->
        case open_local_forward(database, connection) do
          {:ok, local_port} ->
            monitor_ref = Process.monitor(connection)

            {:ok,
             %__MODULE__{
               database_id: database.id,
               ssh_connection: connection,
               ssh_monitor: monitor_ref,
               local_port: local_port,
               key_dir: key_dir
             }}

          {:error, reason} ->
            close_ssh(connection)
            cleanup_key_dir(key_dir)
            {:error, reason}
        end

      {:error, reason} ->
        cleanup_key_dir(key_dir)
        {:error, reason}
    end
  end

  defp ensure_tunnel_fields(database) do
    required = [
      {:ssh_host, database.ssh_host},
      {:ssh_username, database.ssh_username},
      {:ssh_private_key, database.ssh_private_key},
      {:ssh_host_key_fingerprint, database.ssh_host_key_fingerprint},
      {:host, database.host}
    ]

    case Enum.find(required, fn {_field, value} -> blank?(value) end) do
      nil -> :ok
      {field, _value} -> {:error, {:missing_tunnel_field, field}}
    end
  end

  defp connect_ssh(database, key_dir) do
    opts = [
      user: to_charlist(database.ssh_username),
      user_dir: to_charlist(key_dir),
      silently_accept_hosts: {:sha256, host_acceptor(database.ssh_host_key_fingerprint)},
      save_accepted_host: false,
      user_interaction: false,
      quiet_mode: true
    ]

    opts =
      if blank?(database.ssh_passphrase) do
        opts
      else
        Keyword.put(opts, :rsa_pass_phrase, to_charlist(database.ssh_passphrase))
      end

    case ssh_connect(
           to_charlist(database.ssh_host),
           database.ssh_port || 22,
           opts,
           @connect_timeout
         ) do
      {:ok, connection} -> {:ok, connection}
      {:error, reason} -> {:error, {:ssh_connect_failed, reason}}
    end
  end

  defp open_local_forward(database, connection) do
    target_port = database.port || Database.default_port(database.driver)

    case ssh_tcpip_tunnel_to_server(
           connection,
           {127, 0, 0, 1},
           0,
           to_charlist(database.host),
           target_port,
           @connect_timeout
         ) do
      {:ok, local_port} -> {:ok, local_port}
      {:error, reason} -> {:error, {:ssh_forward_failed, reason}}
    end
  end

  defp prepare_key_dir(%Database{} = database) do
    key_dir = Path.join(tunnel_key_root(), database.id)

    with {:ok, _} <- File.rm_rf(key_dir),
         :ok <- File.mkdir_p(key_dir),
         :ok <- File.chmod(key_dir, 0o700),
         :ok <- File.write(Path.join(key_dir, "id_rsa"), database.ssh_private_key || ""),
         :ok <- File.chmod(Path.join(key_dir, "id_rsa"), 0o600),
         :ok <- File.write(Path.join(key_dir, "id_rsa.pub"), database.ssh_public_key || ""),
         :ok <- File.chmod(Path.join(key_dir, "id_rsa.pub"), 0o644) do
      {:ok, key_dir}
    else
      {:error, reason} -> {:error, {:ssh_key_dir_failed, reason}}
    end
  end

  defp tunnel_key_root do
    Application.get_env(
      :trifle,
      :ssh_tunnel_key_root,
      Path.join(System.tmp_dir!(), "trifle_ssh_tunnels")
    )
  end

  defp host_acceptor(expected_fingerprint) do
    fn _peer_name, _port, fingerprint ->
      fingerprint_matches?(expected_fingerprint, fingerprint)
    end
  end

  defp fingerprint_matches?(expected, actual) do
    actual = normalize_fingerprint(actual)
    expected = normalize_fingerprint(expected)
    expected == actual || expected == String.replace_prefix(actual, "SHA256:", "")
  end

  defp normalize_fingerprint(value) when is_list(value),
    do: value |> to_string() |> normalize_fingerprint()

  defp normalize_fingerprint(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace_suffix("=", "")
  end

  defp close_ssh(nil), do: :ok

  defp close_ssh(connection) when is_pid(connection) do
    ssh_close(connection)
  catch
    _, _ -> :ok
  end

  defp ssh_start, do: apply(:ssh, :start, [])

  defp ssh_connect(host, port, opts, timeout) do
    apply(:ssh, :connect, [host, port, opts, timeout])
  end

  defp ssh_tcpip_tunnel_to_server(
         connection,
         listen_host,
         listen_port,
         target_host,
         target_port,
         timeout
       ) do
    apply(:ssh, :tcpip_tunnel_to_server, [
      connection,
      listen_host,
      listen_port,
      target_host,
      target_port,
      timeout
    ])
  end

  defp ssh_close(connection), do: apply(:ssh, :close, [connection])

  defp cleanup_key_dir(nil), do: :ok

  defp cleanup_key_dir(key_dir) do
    _ = File.rm_rf(key_dir)
    :ok
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false
end
