defmodule Trifle.Chat.TraceTools do
  @moduledoc false

  alias Trifle.Chat.Notifier
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.Source
  alias Trifle.Traces.{Reader, RecordData}
  alias TrifleApp.TracesLive.Query

  @states ~w(running success warning error)
  @max_search_limit 20
  @page_bytes 8_000
  @page_entries 40
  @metadata_preview_bytes 4_000

  def definitions do
    source_id = %{
      "type" => "string",
      "description" =>
        "Database ID from list_trace_sources or a trace result. Defaults to the active trace source, or the only available trace source."
    }

    [
      definition("list_trace_sources", "List accessible databases with Traces enabled.", %{}),
      definition(
        "search_traces",
        "Browse or search the trace index newest first by trace start time. With no time bounds, searches all retained traces. " <>
          "Results are summaries. Use read_trace with each result's source_id and reference to inspect its entries and metadata.",
        %{
          "source_id" => source_id,
          "path" => %{
            "type" => "string",
            "description" =>
              "Case-sensitive trace path or whole slash-delimited prefix, e.g. jobs/calculation. Includes descendant paths."
          },
          "tags" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "Exact, case-sensitive tags. Can be combined with path."
          },
          "tag_mode" => %{
            "type" => "string",
            "enum" => ~w(all any),
            "description" => "Match all supplied tags by default, or any of them."
          },
          "state" => %{"type" => "string", "enum" => @states},
          "duration_min" => %{
            "type" => "integer",
            "minimum" => 0,
            "description" => "Milliseconds."
          },
          "from" => %{"type" => "string", "description" => "Inclusive ISO 8601 time with offset."},
          "to" => %{"type" => "string", "description" => "Exclusive ISO 8601 time with offset."},
          "limit" => %{
            "type" => "integer",
            "minimum" => 1,
            "maximum" => @max_search_limit,
            "description" => "Number of matches to return. Defaults to 10."
          },
          "cursor" => %{
            "type" => "string",
            "description" =>
              "next_cursor from the previous page. Reuse the same source and filters."
          }
        }
      ),
      definition(
        "read_trace",
        "Read a specific trace's metadata and a page of its recorded entries, including logs, return values, and attachment descriptors. " <>
          "Use the returned next arguments to continue. Use section=metadata to read just metadata " <>
          "or section=attachment with a media entry's part and row to read its text, including offloaded log messages and return values.",
        %{
          "source_id" => source_id,
          "reference" => %{"type" => "string", "description" => "Exact trace reference."},
          "section" => %{
            "type" => "string",
            "enum" => ~w(entries metadata attachment),
            "default" => "entries"
          },
          "part" => %{"type" => "integer", "minimum" => 1, "default" => 1},
          "row" => %{"type" => "integer", "minimum" => 0, "default" => 0},
          "offset" => %{
            "type" => "integer",
            "minimum" => 0,
            "description" => "Byte offset from next when text or metadata spans pages."
          }
        },
        ["reference"]
      )
    ]
  end

  def execute(name, args, context) do
    with %OrganizationMembership{organization_id: org_id} = membership when is_binary(org_id) <-
           context[:membership] do
      run(name, args, context, membership, Application.get_env(:trifle, :trace_reader, Reader))
    else
      _ -> error("Workspace membership is unavailable for this request.")
    end
  end

  defp run("list_trace_sources", _args, context, membership, _reader) do
    sources = Reader.sources(membership)

    {:ok,
     %{
       status: "ok",
       sources: Enum.map(sources, &%{id: Source.id(&1), name: Source.display_name(&1)}),
       default_source_id: default_source(sources, context[:source])
     }}
  end

  defp run("search_traces", args, context, membership, reader) do
    with {:ok, filters} <- search_filters(args),
         {:ok, id} <- source_id(args, context, membership),
         :ok <- Notifier.notify(context, {:progress, :searching_traces}),
         {:ok, result} <- reader.search(membership, id, filters) do
      {:ok,
       %{
         status: "ok",
         source_id: id,
         traces: Enum.map(result.traces, &summary(&1, id)),
         next_cursor: result.cursor
       }}
    else
      reason -> read_error(reason)
    end
  end

  defp run("read_trace", args, context, membership, reader) do
    with {:ok, reference} <- string_arg(args, "reference", 1024),
         :ok <- check(reference != nil, "reference is required."),
         {:ok, position} <- read_position(args),
         {:ok, id} <- source_id(args, context, membership),
         :ok <- Notifier.notify(context, {:progress, :reading_trace}) do
      read_trace(reader, membership, %{source_id: id, reference: reference}, position)
    else
      reason -> read_error(reason)
    end
  end

  defp read_trace(reader, membership, page_args, %{section: "attachment"} = position) do
    %{source_id: id, reference: reference} = page_args

    with {:ok, artifact} <-
           reader.artifact(membership, id, reference, position.part, position.row),
         :ok <- check(Reader.text_artifact?(artifact), "The attachment is not readable text."),
         :ok <- check(valid_offset?(artifact.body, position.offset), "Invalid attachment offset.") do
      {text, next} = text_chunk(artifact.body, position.offset, @page_bytes)

      {:ok,
       %{
         status: "ok",
         source_id: id,
         reference: reference,
         name: artifact.name,
         text: text,
         next: if(next, do: Map.merge(page_args, %{position | offset: next}))
       }}
    else
      reason -> read_error(reason)
    end
  end

  defp read_trace(reader, membership, page_args, position) do
    %{source_id: id, reference: reference} = page_args

    case reader.contents(membership, id, reference, position[:part]) do
      {:ok, %{record: record, entries: entries}} ->
        trace = summary(record, id)
        metadata = RecordData.metadata(record)
        metadata = {metadata, Jason.encode!(metadata)}

        case position do
          %{section: "entries"} -> read_entries(trace, metadata, entries, position, page_args)
          %{section: "metadata"} -> read_metadata(trace, metadata, position.offset, page_args)
        end

      error ->
        read_error(error)
    end
  end

  defp definition(name, description, properties, required \\ []) do
    %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => description,
        "parameters" => %{
          "type" => "object",
          "properties" => properties,
          "required" => required,
          "additionalProperties" => false
        }
      }
    }
  end

  defp source_id(args, context, membership) do
    with {:ok, id} <- string_arg(args, "source_id", 255) do
      if id do
        {:ok, id}
      else
        sources = Reader.sources(membership)

        case default_source(sources, context[:source]) do
          nil when sources == [] -> error("No accessible database has Traces enabled.")
          nil -> error("Choose a source_id from list_trace_sources.")
          id -> {:ok, id}
        end
      end
    end
  end

  defp default_source(sources, %Source{} = active) do
    if Source.type(active) == :database and
         Enum.any?(sources, &(Source.id(&1) == Source.id(active))),
       do: Source.id(active),
       else: default_source(sources, nil)
  end

  defp default_source([source], _), do: Source.id(source)
  defp default_source(_, _), do: nil

  defp search_filters(args) do
    mode = Map.get(args, "tag_mode", "all")
    state = args["state"]
    duration = args["duration_min"]
    limit = Map.get(args, "limit", 10)

    with {:ok, path} <- string_arg(args, "path", 2048),
         {:ok, cursor} <- string_arg(args, "cursor", 4096),
         {:ok, tags} <- tags(args),
         {:ok, from} <- time(args, "from"),
         {:ok, to} <- time(args, "to"),
         :ok <-
           check(
             is_nil(from) or is_nil(to) or DateTime.before?(from, to),
             "from must precede to."
           ),
         :ok <- check(mode in ~w(all any), "tag_mode must be all or any."),
         :ok <- check(is_nil(state) or state in @states, "Invalid trace state."),
         :ok <-
           check(
             is_nil(duration) or (is_integer(duration) and duration >= 0),
             "Invalid duration_min."
           ),
         :ok <- check(limit in 1..@max_search_limit, "limit must be an integer from 1 to 20.") do
      {:ok,
       [
         limit: limit,
         segment: path,
         tags: %{if(mode == "all", do: :all, else: :any) => tags},
         state: state,
         duration_min: duration,
         from: from,
         to: to,
         cursor: cursor
       ]
       |> Enum.reject(fn {_, value} -> is_nil(value) end)}
    end
  end

  defp tags(args) do
    tags = Map.get(args, "tags", [])

    if is_list(tags) and length(tags) <= 20 and Enum.all?(tags, &valid_string?(&1, 1024)),
      do: {:ok, Enum.uniq(tags)},
      else: error("tags must be an array of up to 20 non-empty strings.")
  end

  defp time(args, key) do
    with {:ok, value} <- string_arg(args, key, 64),
         false <- is_nil(value),
         {:ok, at, _} <- DateTime.from_iso8601(value) do
      {:ok, at}
    else
      true -> {:ok, nil}
      _ -> error("#{key} must be an ISO 8601 timestamp with a time zone offset.")
    end
  end

  defp read_position(args) do
    section = Map.get(args, "section", "entries")
    part = Map.get(args, "part", 1)
    row = Map.get(args, "row", 0)
    offset = Map.get(args, "offset", 0)

    with :ok <- check(is_integer(offset) and offset >= 0, "Invalid offset.") do
      case section do
        section when section in ~w(entries attachment) ->
          with :ok <- check(is_integer(part) and part >= 1, "Invalid part."),
               :ok <- check(is_integer(row) and row >= 0, "Invalid row.") do
            {:ok, %{section: section, part: part, row: row, offset: offset}}
          end

        "metadata" ->
          {:ok, %{section: section, offset: offset}}

        _ ->
          error("section must be entries, metadata, or attachment.")
      end
    end
  end

  defp summary(record, id) do
    Map.merge(RecordData.summary(record), %{
      source_id: id,
      url: Query.url(%{"source_id" => id, "reference" => record.reference})
    })
  end

  defp read_entries(trace, {metadata, encoded_metadata}, entries, position, page_args) do
    page_entries = Enum.drop(entries, position.row)

    with :ok <- check(position.row == 0 or page_entries != [], "Invalid entry row."),
         {:ok, rows, next} <- entry_page(page_entries, position, @page_bytes, []) do
      next = next || next_part(position.part, trace.part_count)

      {:ok,
       %{
         status: "ok",
         trace: trace,
         part: if(trace.part_count > 0, do: position.part),
         entries: rows,
         next: if(next, do: Map.merge(page_args, next))
       }
       |> put_metadata_preview(metadata, encoded_metadata, page_args)}
    end
  end

  defp put_metadata_preview(result, metadata, encoded, _page_args)
       when byte_size(encoded) <= @metadata_preview_bytes,
       do: Map.put(result, :metadata, metadata)

  defp put_metadata_preview(result, _metadata, encoded, page_args) do
    {chunk, next} = text_chunk(encoded, 0, @metadata_preview_bytes)

    Map.merge(result, %{
      metadata_json_fragment: chunk,
      next_metadata: Map.merge(page_args, %{section: "metadata", offset: next})
    })
  end

  defp read_metadata(trace, {metadata, encoded}, offset, page_args) do
    cond do
      offset == 0 and byte_size(encoded) <= @page_bytes ->
        {:ok, %{status: "ok", trace: trace, metadata: metadata}}

      valid_offset?(encoded, offset) ->
        {chunk, next} = text_chunk(encoded, offset, @page_bytes)

        {:ok,
         %{
           status: "ok",
           trace: trace,
           metadata_json_fragment: chunk,
           next: if(next, do: Map.merge(page_args, %{section: "metadata", offset: next}))
         }}

      true ->
        error("Invalid metadata offset. Use the offset returned by read_trace.")
    end
  end

  defp entry_page([], %{offset: 0}, _remaining, rows), do: {:ok, Enum.reverse(rows), nil}
  defp entry_page([], _position, _remaining, _rows), do: error("Invalid entry position.")

  defp entry_page([_ | _], position, remaining, rows)
       when remaining <= 0 or length(rows) == @page_entries,
       do: {:ok, Enum.reverse(rows), position}

  defp entry_page([entry | rest], position, remaining, rows) do
    message = Reader.field(entry, :message)
    text = if is_binary(message), do: message, else: Jason.encode!(message)

    if valid_offset?(text, position.offset) do
      {chunk, offset} = text_chunk(text, position.offset, remaining)

      row =
        Map.new([:at, :type, :state, :level, :size], &{&1, Reader.field(entry, &1)})
        |> Map.merge(%{
          row: position.row,
          offset: position.offset,
          message: chunk,
          message_continues: not is_nil(offset)
        })

      cond do
        offset == position.offset ->
          {:ok, Enum.reverse(rows), position}

        offset ->
          {:ok, Enum.reverse([row | rows]), %{position | offset: offset}}

        true ->
          entry_page(
            rest,
            %{position | row: position.row + 1, offset: 0},
            remaining - byte_size(chunk),
            [row | rows]
          )
      end
    else
      error("Invalid message offset. Use the offset returned by read_trace.")
    end
  end

  defp next_part(part, count) when part < count, do: %{part: part + 1, row: 0, offset: 0}
  defp next_part(_, _), do: nil

  defp valid_offset?(_text, 0), do: true

  defp valid_offset?(text, offset),
    do: offset < byte_size(text) and :binary.at(text, offset) not in 128..191

  defp text_chunk(text, offset, limit) do
    chunk = String.byte_slice(text, offset, limit)
    next = offset + byte_size(chunk)
    {chunk, if(next < byte_size(text), do: next)}
  end

  defp string_arg(args, key, max_bytes) do
    value = args[key]

    cond do
      is_nil(value) -> {:ok, nil}
      valid_string?(value, max_bytes) -> {:ok, value}
      true -> error("#{key} must be a non-empty string.")
    end
  end

  defp valid_string?(value, max_bytes),
    do:
      is_binary(value) and byte_size(value) <= max_bytes and String.trim(value) != "" and
        not String.contains?(value, <<0>>)

  defp check(true, _message), do: :ok
  defp check(false, message), do: error(message)

  defp read_error({:error, %{status: "error"}} = result), do: result
  defp read_error({:error, :unavailable}), do: error("This trace source is unavailable.")

  defp read_error({:error, :not_found}),
    do: error("The trace or requested part or attachment was not found.")

  defp read_error({:error, :too_large}),
    do: error("The attachment exceeds the trace reader limit.")

  defp read_error({:error, :storage_unavailable}),
    do: error("The trace index or payload storage could not be read.")

  defp error(message), do: {:error, %{status: "error", error: message}}
end
