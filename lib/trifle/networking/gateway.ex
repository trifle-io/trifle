defmodule Trifle.Networking.Gateway do
  @moduledoc "Private, mutually authenticated interface to the shared network gateway."

  def configured? do
    config = config()

    Enum.all?(
      [:url, :ca_file, :cert_file, :key_file],
      &(is_binary(config[&1]) and config[&1] != "")
    )
  end

  def configure(connection) do
    payload =
      identity(connection)
      |> Map.merge(%{
        hostname: "trifle-" <> connection.id,
        enabled: connection.enabled,
        auth_key: connection.auth_key || ""
      })

    request(:put, "/v1/connections", payload)
  end

  def status(connection), do: request(:post, "/v1/status", identity(connection))
  def put_route(route), do: request(:put, "/v1/routes", route)

  def identity(connection) do
    %{
      organization_id: connection.organization_id,
      id: connection.id,
      generation: connection.generation
    }
  end

  def request(method, path, payload) do
    with {:ok, uri, ssl} <- transport_options() do
      url = URI.to_string(%{uri | path: path, query: nil})
      body = Jason.encode!(payload)
      request = {String.to_charlist(url), [], ~c"application/json", body}

      case :httpc.request(
             method,
             request,
             [ssl: ssl, timeout: 15_000, connect_timeout: 5_000, autoredirect: false],
             body_format: :binary
           ) do
        {:ok, {{_, code, _}, _, response}} when code in 200..299 -> Jason.decode(response)
        {:ok, {{_, code, _}, _, _}} -> {:error, {:gateway_status, code}}
        {:error, _} -> {:error, :gateway_unavailable}
      end
    end
  end

  # The upgrade carries raw bytes in both directions. Database/S3 credentials
  # remain part of their native protocol, never a gateway job or persisted body.
  def open_stream(route) do
    with {:ok, uri, ssl} <- transport_options(),
         {:ok, socket} <-
           :ssl.connect(
             String.to_charlist(uri.host),
             uri.port,
             [:binary, active: false, packet: :line, packet_size: 8192] ++ ssl,
             5_000
           ) do
      body = Jason.encode!(route)

      request = [
        "POST /v1/streams HTTP/1.1\r\nHost: ",
        uri.host,
        "\r\nConnection: Upgrade\r\nUpgrade: trifle-stream\r\nContent-Type: application/json\r\nContent-Length: ",
        Integer.to_string(byte_size(body)),
        "\r\n\r\n",
        body
      ]

      result =
        with :ok <- :ssl.send(socket, request),
             {:ok, "HTTP/1.1 101 " <> _} <- :ssl.recv(socket, 0, 15_000),
             :ok <- read_headers(socket, 0),
             :ok <- :ssl.setopts(socket, packet: :raw),
             do: {:ok, socket}

      case result do
        {:ok, socket} ->
          {:ok, socket}

        _ ->
          :ssl.close(socket)
          {:error, :tailnet_unavailable}
      end
    else
      _ -> {:error, :gateway_unavailable}
    end
  end

  defp read_headers(_socket, count) when count > 32, do: {:error, :invalid_headers}

  defp read_headers(socket, count) do
    case :ssl.recv(socket, 0, 5_000) do
      {:ok, "\r\n"} -> :ok
      {:ok, _} -> read_headers(socket, count + 1)
      error -> error
    end
  end

  def transport_options do
    config = config()
    uri = URI.parse(config[:url] || "")

    if configured?() and uri.scheme == "https" and is_binary(uri.host) and is_nil(uri.userinfo) do
      {:ok, uri,
       [
         verify: :verify_peer,
         cacertfile: String.to_charlist(config[:ca_file]),
         certfile: String.to_charlist(config[:cert_file]),
         keyfile: String.to_charlist(config[:key_file]),
         server_name_indication: String.to_charlist(uri.host),
         customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
         versions: [:"tlsv1.3"]
       ]}
    else
      {:error, :gateway_not_configured}
    end
  end

  defp config, do: Application.get_env(:trifle, __MODULE__, [])
end
