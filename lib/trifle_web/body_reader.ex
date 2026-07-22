defmodule TrifleWeb.BodyReader do
  @moduledoc false

  def read_body(conn, opts) do
    if gzip_encoded?(conn) do
      read_gzip_body(conn, opts)
    else
      read_plain_body(conn, opts)
    end
  end

  defp read_plain_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = maybe_store_raw_body(conn, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = maybe_store_raw_body(conn, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_gzip_body(conn, opts) do
    limit = Keyword.get(opts, :length, 8_000_000)

    with {:ok, compressed, conn} <- read_compressed_body(conn, opts, "", limit),
         {:ok, body} <- gunzip(compressed, limit) do
      {:ok, body, conn}
    else
      {:error, :too_large, conn} -> {:more, "", conn}
      {:error, :too_large} -> {:more, "", conn}
      {:error, reason, _conn} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_compressed_body(conn, opts, acc, limit) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, chunk, conn} ->
        compressed = acc <> chunk
        conn = maybe_store_raw_body(conn, chunk)

        if byte_size(compressed) <= limit,
          do: {:ok, compressed, conn},
          else: {:error, :too_large, conn}

      {:more, chunk, conn} ->
        compressed = acc <> chunk
        conn = maybe_store_raw_body(conn, chunk)

        if byte_size(compressed) <= limit,
          do: read_compressed_body(conn, opts, compressed, limit),
          else: {:error, :too_large, conn}

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp gunzip(body, limit) do
    zstream = :zlib.open()

    try do
      :ok = :zlib.inflateInit(zstream, 31)

      case inflate_chunks(zstream, body_chunks(body), limit, [], 0) do
        {:ok, chunks} -> {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary()}
        {:error, reason} -> {:error, reason}
      end
    after
      try do
        :zlib.inflateEnd(zstream)
      catch
        _, _ -> :ok
      end

      :zlib.close(zstream)
    end
  rescue
    _ -> {:error, :invalid_gzip}
  catch
    _, _ -> {:error, :invalid_gzip}
  end

  defp inflate_chunks(_zstream, [], _limit, chunks, _size), do: {:ok, chunks}

  defp inflate_chunks(zstream, [compressed | rest], limit, chunks, size) do
    inflated = :zlib.inflate(zstream, compressed)
    inflated_size = :erlang.iolist_size(inflated)

    if size + inflated_size > limit do
      {:error, :too_large}
    else
      inflate_chunks(zstream, rest, limit, [inflated | chunks], size + inflated_size)
    end
  end

  defp body_chunks(body), do: body_chunks(body, [])
  defp body_chunks("", chunks), do: Enum.reverse(chunks)

  defp body_chunks(body, chunks) do
    chunk_size = min(byte_size(body), 1024)
    <<chunk::binary-size(chunk_size), rest::binary>> = body
    body_chunks(rest, [chunk | chunks])
  end

  defp gzip_encoded?(conn) do
    conn
    |> Plug.Conn.get_req_header("content-encoding")
    |> Enum.any?(&(String.downcase(String.trim(&1)) == "gzip"))
  end

  defp maybe_store_raw_body(%Plug.Conn{} = conn, body) when is_binary(body) do
    if stripe_webhook_request?(conn) do
      Plug.Conn.assign(conn, :raw_body, (conn.assigns[:raw_body] || "") <> body)
    else
      conn
    end
  end

  defp stripe_webhook_request?(%Plug.Conn{method: "POST", request_path: "/webhooks/stripe"}),
    do: true

  defp stripe_webhook_request?(_conn), do: false
end
