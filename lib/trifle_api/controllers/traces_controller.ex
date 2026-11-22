defmodule TrifleApi.TracesController do
  use TrifleApi, :controller

  alias Trifle.Organizations.Database
  alias Trifle.Traces.{Reader, RecordData}
  alias Trifle.Traces.Driver.Index.Query, as: IndexQuery

  @states ~w(running success warning error)
  @max_integer 9_223_372_036_854_775_807

  plug TrifleApi.Plugs.AuthenticateBySourceToken, %{mode: :read}
  plug :require_traces

  def index(conn, params) do
    with {:ok, limit, filters} <- search_filters(params),
         # Look ahead so a full last page still returns a null cursor.
         {:ok, %{traces: traces}} <-
           read(conn, :search, [Keyword.put(filters, :limit, limit + 1)]) do
      {page, remaining} = Enum.split(traces, limit)
      next_cursor = if remaining != [], do: IndexQuery.encode_cursor(List.last(page))

      json(conn, %{
        data: Enum.map(page, &RecordData.summary/1),
        pagination: %{next_cursor: next_cursor}
      })
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def show(conn, %{"reference" => reference}) do
    case read(conn, :detail, [reference]) do
      {:ok, record} ->
        json(conn, %{data: Map.merge(RecordData.summary(record), RecordData.metadata(record))})

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  def entries(conn, %{"reference" => reference} = params) do
    with {:ok, part} <- integer(params, "part", 1, 1..@max_integer),
         {:ok, row} <- integer(params, "row", 0, 0..@max_integer),
         {:ok, limit} <- integer(params, "limit", 100, 1..200),
         {:ok, %{record: record, entries: entries}} <- read(conn, :contents, [reference, part]),
         {:ok, page, next} <- entry_page(entries, record, part, row, limit) do
      json(conn, %{data: page, pagination: %{next: next}})
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def attachments(conn, %{"reference" => reference} = params) do
    with {:ok, after_part} <- integer(params, "after_part", 0, 0..@max_integer),
         {:ok, result} <- read(conn, :attachments, [reference, after_part]) do
      json(conn, %{
        data: Enum.map(result.attachments, &attachment_data(&1, reference)),
        pagination: %{next_after_part: result.next_part}
      })
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def download_attachment(conn, %{"reference" => reference, "attachment_id" => id}) do
    with {:ok, part, row} <- attachment_location(id),
         {:ok, artifact} <- read(conn, :artifact, [reference, part, row]) do
      send_download(conn, {:binary, artifact.body},
        filename: artifact.name,
        content_type: "application/octet-stream",
        disposition: :attachment
      )
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  defp attachment_data(%{name: name, size: size, part: part, row: row}, reference) do
    id = Base.url_encode64(<<part::64, row::64>>, padding: false)

    %{
      id: id,
      name: name,
      size: size,
      download_url: ~p"/api/v1/traces/#{reference}/attachments/#{id}"
    }
  end

  defp attachment_location(id) when byte_size(id) == 22 do
    case Base.url_decode64(id, padding: false) do
      {:ok, <<part::64, row::64>>} when part > 0 -> {:ok, part, row}
      _ -> {:error, :not_found}
    end
  end

  defp attachment_location(_), do: {:error, :not_found}

  defp require_traces(conn, _opts) do
    conn =
      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")

    if Database.traces_configured?(conn.assigns.current_database),
      do: conn,
      else: conn |> render_error(:unavailable) |> halt()
  end

  # Only the authenticated source header selects a database. The reader also
  # rechecks its organization and availability before opening either store.
  defp read(conn, operation, args) do
    database = conn.assigns.current_database
    reader = Application.get_env(:trifle, :trace_reader, Reader)
    apply(reader, operation, [%{organization_id: database.organization_id}, database.id | args])
  end

  defp search_filters(params) do
    with {:ok, path} <- text(params["path"], "path", 2048),
         {:ok, state} <- choice(params["state"], "state", @states),
         {:ok, tags} <- tags(params["tags"]),
         {:ok, tag_mode} <- choice(Map.get(params, "tag_mode", "all"), "tag_mode", ~w(all any)),
         {:ok, from} <- timestamp(params["from"], "from"),
         {:ok, to} <- timestamp(params["to"], "to"),
         :ok <- ordered_range(from, to),
         {:ok, duration} <- integer(params, "duration_min", nil, 0..@max_integer),
         {:ok, limit} <- integer(params, "limit", 20, 1..100),
         {:ok, cursor} <- cursor(params["cursor"]) do
      {:ok, limit,
       [
         segment: path,
         state: state,
         tags: %{if(tag_mode == "any", do: :any, else: :all) => tags},
         from: from,
         to: to,
         duration_min: duration,
         cursor: cursor
       ]}
    end
  end

  defp tags(nil), do: {:ok, []}

  defp tags(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> tags()
  end

  defp tags(values) when is_list(values) and length(values) in 1..20 do
    if Enum.all?(values, &valid_text?(&1, 1024)),
      do: {:ok, Enum.uniq(values)},
      else: invalid("tags")
  end

  defp tags(_), do: invalid("tags")

  defp integer(params, key, default, range) do
    case Map.fetch(params, key) do
      :error ->
        {:ok, default}

      {:ok, value} when is_binary(value) and byte_size(value) <= 19 ->
        case Integer.parse(value) do
          {integer, ""} -> if(integer in range, do: {:ok, integer}, else: invalid(key))
          _ -> invalid(key)
        end

      _ ->
        invalid(key)
    end
  end

  defp choice(nil, _key, _choices), do: {:ok, nil}

  defp choice(value, key, choices),
    do: if(value in choices, do: {:ok, value}, else: invalid(key))

  defp text(nil, _key, _max_bytes), do: {:ok, nil}

  defp text(value, key, max_bytes),
    do: if(valid_text?(value, max_bytes), do: {:ok, value}, else: invalid(key))

  defp valid_text?(value, max_bytes) do
    is_binary(value) and byte_size(value) <= max_bytes and String.trim(value) != "" and
      not String.contains?(value, <<0>>)
  end

  defp timestamp(nil, _key), do: {:ok, nil}

  defp timestamp(value, key) when is_binary(value) and byte_size(value) <= 64 do
    case DateTime.from_iso8601(value) do
      {:ok, timestamp, _offset} -> {:ok, timestamp}
      _ -> invalid(key)
    end
  end

  defp timestamp(_value, key), do: invalid(key)

  defp ordered_range(nil, _to), do: :ok
  defp ordered_range(_from, nil), do: :ok

  defp ordered_range(from, to) do
    if DateTime.before?(from, to),
      do: :ok,
      else: {:error, {:bad_request, "from must precede to"}}
  end

  defp cursor(nil), do: {:ok, nil}

  defp cursor(value) when is_binary(value) and byte_size(value) <= 4096 do
    %{reference: reference} = IndexQuery.decode_cursor(value)
    if valid_text?(reference, 1024), do: {:ok, value}, else: invalid("cursor")
  rescue
    ArgumentError -> invalid("cursor")
  end

  defp cursor(_), do: invalid("cursor")

  defp entry_page(entries, record, part, row, limit) do
    case Enum.drop(entries, row) do
      [] when row > 0 ->
        {:error, :not_found}

      remaining ->
        {page, rest} = Enum.split(remaining, limit)

        next =
          cond do
            rest != [] -> %{part: part, row: row + limit}
            part < record.parts -> %{part: part + 1, row: 0}
            true -> nil
          end

        data =
          Enum.with_index(page, row)
          |> Enum.map(fn {entry, index} ->
            fields =
              Map.new(
                [:at, :type, :state, :level, :message, :size],
                &{&1, Reader.field(entry, &1)}
              )
              |> Map.merge(%{part: part, row: index})

            case Reader.attachment(entry, part, index) do
              nil ->
                fields

              attachment ->
                Map.put(fields, :attachment, attachment_data(attachment, record.reference))
            end
          end)

        {:ok, data, next}
    end
  end

  defp invalid(key), do: {:error, {:bad_request, "Invalid #{key} parameter"}}

  defp render_error(conn, {:bad_request, detail}), do: error_response(conn, 400, detail)

  defp render_error(conn, :unavailable),
    do: error_response(conn, 404, "Traces are unavailable for this source")

  defp render_error(conn, :not_found),
    do: error_response(conn, 404, "Trace, part, or attachment not found")

  defp render_error(conn, :too_large),
    do: error_response(conn, 413, "Attachment exceeds the configured size limit")

  defp render_error(conn, :storage_unavailable),
    do: error_response(conn, 503, "Trace storage is unavailable")

  defp error_response(conn, status, detail),
    do: conn |> put_status(status) |> json(%{errors: %{detail: detail}})
end
