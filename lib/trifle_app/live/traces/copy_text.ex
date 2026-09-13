defmodule TrifleApp.TracesLive.CopyText do
  @moduledoc false
  alias Trifle.Traces.Reader

  # Only the entries supplied by the view are copied. Never read storage here.
  def format(record, entries, loaded_parts) do
    header = """
    Trace: #{record.key}
    Reference: #{record.reference}
    State: #{record.state}
    Started: #{timestamp(record.first_at)}
    Last: #{timestamp(record.last_at)}
    Duration: #{record.duration} ms
    Loaded parts: #{loaded_parts}/#{record.parts}
    Loaded entries: #{length(entries)}
    Tags: #{Jason.encode!(record.tags)}

    Metadata / arguments:
    #{Jason.encode!(record.meta, pretty: true)}

    Context:
    #{Jason.encode!(record.context, pretty: true)}

    Entries (loaded parts only; attachments excluded):
    """

    entries
    |> Enum.reduce([header], fn %{entry: entry}, chunks ->
      if to_string(Reader.field(entry, :type)) == "media" do
        chunks
      else
        state = Reader.field(entry, :state) || :success
        type = Reader.field(entry, :type) || :text
        at = timestamp(Reader.field(entry, :at))
        level = Reader.field(entry, :level)

        indent =
          if is_integer(level), do: String.duplicate("  ", min(max(level, 0), 12)), else: ""

        message = Reader.field(entry, :message)
        message = if is_binary(message), do: message, else: inspect(message, pretty: true)
        ["#{at} [#{state}/#{type}] #{indent}#{message}\n" | chunks]
      end
    end)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value, :second) do
      {:ok, date} -> timestamp(date)
      _ -> "—"
    end
  end

  defp timestamp(nil), do: "—"
  defp timestamp(value) when is_binary(value), do: value
  defp timestamp(_), do: "—"
end
