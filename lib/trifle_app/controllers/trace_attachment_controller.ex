defmodule TrifleApp.TraceAttachmentController do
  use TrifleApp, :controller
  alias Trifle.Traces.{Media, Reader}
  alias TrifleApp.TraceDownload

  def show(
        conn,
        %{"source_id" => id, "reference" => reference, "part" => part, "row" => row} = params
      ) do
    with {part, ""} <- Integer.parse(part),
         {row, ""} <- Integer.parse(row),
         {:ok, artifact} <-
           Reader.artifact(conn.assigns[:current_membership], id, reference, part, row) do
      conn =
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-content-type-options", "nosniff")

      if params["inline"] == "true",
        do: send_inline(conn, artifact),
        else: TraceDownload.send_artifact(conn, artifact)
    else
      {:error, :too_large} -> send_resp(conn, 413, "Attachment exceeds the configured size limit")
      _ -> send_resp(conn, 404, "Attachment not found or unavailable")
    end
  end

  def show(conn, _), do: send_resp(conn, 404, "Attachment not found or unavailable")

  # The type is decided from the name and the leading bytes only; the rest of
  # the file is streamed straight from storage.
  defp send_inline(conn, artifact) do
    mime =
      with {:ok, head} <- Reader.head(artifact, 16),
           do: Media.content_type(%{name: artifact.name, body: head}),
           else: (_ -> nil)

    if mime do
      send_inline(conn, artifact, mime)
    else
      send_resp(conn, 415, "Inline preview is unavailable for this attachment")
    end
  end

  defp send_inline(conn, artifact, mime) do
    size = artifact.size
    conn = put_resp_header(conn, "accept-ranges", "bytes")

    # A range request maps onto the same range in storage, so seeking in a video
    # reads only the bytes asked for. Ignore If-Range since this endpoint does
    # not issue validators, and ignore multipart ranges.
    range = if get_req_header(conn, "if-range") == [], do: get_req_header(conn, "range"), else: []

    case byte_range(range, size) do
      :invalid ->
        conn |> put_resp_header("content-range", "bytes */#{size}") |> send_resp(416, "")

      {first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> TraceDownload.send_artifact(artifact,
          content_type: mime,
          disposition: :inline,
          status: 206,
          range: {first, last}
        )

      :full ->
        TraceDownload.send_artifact(conn, artifact, content_type: mime, disposition: :inline)
    end
  end

  defp byte_range(["bytes=" <> value], size) when byte_size(value) <= 128 do
    case Regex.run(~r/\A(\d*)-(\d*)\z/, String.trim(value)) do
      [_, "", ""] ->
        :invalid

      [_, "", suffix] ->
        count = String.to_integer(suffix)
        if count > 0 and size > 0, do: {max(size - count, 0), size - 1}, else: :invalid

      [_, first, last] ->
        first = String.to_integer(first)
        last = if last == "", do: size - 1, else: min(String.to_integer(last), size - 1)
        if first < size and first <= last, do: {first, last}, else: :invalid

      _ ->
        :full
    end
  end

  defp byte_range(_, _), do: :full
end
