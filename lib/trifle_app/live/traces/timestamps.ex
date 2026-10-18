defmodule TrifleApp.TracesLive.Timestamps do
  @moduledoc false

  alias Trifle.Traces.Reader
  alias TrifleApp.Format

  def next_mode("raw"), do: "diff"
  def next_mode("diff"), do: "diff_header"
  def next_mode("diff_header"), do: "raw"

  def label("raw"), do: "Full"
  def label("diff"), do: "Diff"
  def label("diff_header"), do: "Diff Head"

  def description("raw"), do: "Original row timestamps"
  def description("diff"), do: "Duration since the previous row"

  def description("diff_header"),
    do: "Duration between headers, including the first and last rows"

  def iso8601(at) when is_float(at) do
    case DateTime.from_unix(timestamp_us(at), :microsecond) do
      {:ok, date} -> date |> DateTime.truncate(:millisecond) |> DateTime.to_iso8601()
      _ -> nil
    end
  end

  def rows(entries, "raw") do
    Enum.with_index(entries, fn item, index -> {item, index + 1, nil} end)
  end

  def rows(entries, mode) when mode in ["diff", "diff_header"] do
    last = length(entries)

    entries
    |> Enum.with_index(1)
    |> Enum.map_reduce(nil, fn {item, number}, previous ->
      # Recompute the last visible boundary as more parts arrive. Intermediate
      # rows never advance the baseline in header mode, regardless of nesting.
      if mode == "diff" or number in [1, last] or
           to_string(Reader.field(item.entry, :type)) == "head" do
        at = timestamp_us(Reader.field(item.entry, :at))
        {{item, number, difference(at, previous, number)}, at}
      else
        {{item, number, nil}, previous}
      end
    end)
    |> elem(0)
  end

  defp difference(nil, _previous, _number), do: "—"
  defp difference(_at, _previous, 1), do: "0ms"
  defp difference(_at, nil, _number), do: "—"
  defp difference(at, previous, _number), do: Format.duration_ms(round((at - previous) / 1_000))

  # Trace payloads use Unix seconds. DateTimes and fractional seconds retain
  # their precision until the difference is rounded to milliseconds.
  defp timestamp_us(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)
  defp timestamp_us(at) when is_integer(at), do: at * 1_000_000
  defp timestamp_us(at) when is_float(at), do: round(at * 1_000_000)

  defp timestamp_us(at) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, at, _offset} -> timestamp_us(at)
      _ -> nil
    end
  end

  defp timestamp_us(_at), do: nil
end
