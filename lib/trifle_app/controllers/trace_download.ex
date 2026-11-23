defmodule TrifleApp.TraceDownload do
  @moduledoc """
  Sends a trace attachment to the client as it is read from storage.

  The attachment is forwarded chunk by chunk, so the memory used by a download
  does not grow with the size of the file.
  """

  import Plug.Conn
  require Logger

  alias Trifle.Traces.Reader

  defmodule Interrupted do
    defexception message: "trace attachment could not be read to the end"
  end

  @doc """
  Streams bytes `first..last` of `artifact` (the whole file by default).

  Options: `:content_type`, `:disposition` (`:attachment` or `:inline`),
  `:status` and `:range` as `{first, last}`.
  """
  def send_artifact(conn, artifact, opts \\ []) do
    {first, last} = Keyword.get(opts, :range, {0, artifact.size - 1})
    disposition = Keyword.get(opts, :disposition, :attachment)
    name = URI.encode(artifact.name, &URI.char_unreserved?/1)

    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_content_type(Keyword.get(opts, :content_type, "application/octet-stream"), nil)
      |> put_resp_header(
        "content-disposition",
        ~s[#{disposition}; filename="#{name}"; filename*=utf-8''#{name}]
      )
      # With a declared length the client can show progress and can tell a
      # complete download from one that was cut short.
      |> put_resp_header("content-length", Integer.to_string(max(last - first + 1, 0)))
      |> send_chunked(Keyword.get(opts, :status, 200))

    forward(conn, artifact, first, last)
  end

  defp forward(conn, artifact, first, last) do
    artifact
    |> Reader.stream(first, last)
    |> Enum.reduce_while(conn, fn body, conn ->
      case chunk(conn, body) do
        {:ok, conn} -> {:cont, conn}
        # The client went away; stop reading from storage.
        {:error, _closed} -> {:halt, conn}
      end
    end)
  rescue
    error ->
      Logger.warning(fn ->
        "[TraceDownload] source_id=#{artifact.source_id} attachment=#{inspect(artifact.name)} " <>
          "interrupted\n" <> Exception.format(:error, error, __STACKTRACE__)
      end)

      # Headers are already sent. Failing the request closes the connection
      # short of the declared length, so the client sees a failed transfer
      # instead of a file that looks complete.
      reraise Interrupted, __STACKTRACE__
  end
end
