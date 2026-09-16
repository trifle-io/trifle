defmodule TrifleApp.TraceAttachmentController do
  use TrifleApp, :controller
  alias Trifle.Traces.{Media, Reader}

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

      if params["inline"] == "true" do
        case Media.content_type(artifact) do
          nil -> send_resp(conn, 415, "Inline preview is unavailable for this attachment")
          mime -> send_inline(conn, artifact, mime)
        end
      else
        send_download(conn, {:binary, artifact.body},
          filename: artifact.name,
          content_type: "application/octet-stream",
          disposition: :attachment
        )
      end
    else
      {:error, :too_large} -> send_resp(conn, 413, "Attachment exceeds the configured size limit")
      _ -> send_resp(conn, 404, "Attachment not found or unavailable")
    end
  end

  def show(conn, _), do: send_resp(conn, 404, "Attachment not found or unavailable")

  defp send_inline(conn, artifact, mime) do
    size = byte_size(artifact.body)
    conn = put_resp_header(conn, "accept-ranges", "bytes")

    # Drivers currently read/decompress the whole artifact. Range responses allow
    # browser seeking, but are not storage-level streaming. Ignore If-Range since
    # this endpoint does not issue validators, and ignore multipart ranges.
    range = if get_req_header(conn, "if-range") == [], do: get_req_header(conn, "range"), else: []

    case byte_range(range, size) do
      :invalid ->
        conn |> put_resp_header("content-range", "bytes */#{size}") |> send_resp(416, "")

      result ->
        {conn, body} =
          case result do
            {first, last} ->
              {conn
               |> put_status(206)
               |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}"),
               binary_part(artifact.body, first, last - first + 1)}

            :full ->
              {conn, artifact.body}
          end

        send_download(conn, {:binary, body},
          filename: artifact.name,
          content_type: mime,
          disposition: :inline
        )
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
