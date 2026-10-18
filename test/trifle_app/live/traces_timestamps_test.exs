defmodule TrifleApp.TracesLive.TimestampsTest do
  use ExUnit.Case, async: true

  alias TrifleApp.TracesLive.Timestamps

  test "fractional Unix timestamps display milliseconds without changing their second-based unit" do
    assert Timestamps.iso8601(1_700_000_000.123456) == "2023-11-14T22:13:20.123Z"
    assert Timestamps.iso8601(1_700_000_000.999999) == "2023-11-14T22:13:20.999Z"
    assert Timestamps.iso8601(1_700_000_000.0) == "2023-11-14T22:13:20.000Z"
    assert Timestamps.iso8601(1.0e30) == nil
  end

  test "row differences span parts and include every entry type" do
    entries =
      entries([
        {:text, 0},
        {:head, 1.25},
        {:text, 1.5},
        {:head, 62.25},
        {:raw, 62.5},
        {:media, 62.75}
      ])

    assert labels(entries, "diff") == ["0ms", "1s250ms", "250ms", "1m750ms", "250ms", "250ms"]
    assert labels(entries, "diff_header") == ["0ms", "1s250ms", nil, "1m1s", nil, "500ms"]

    # Raw mode preserves the original entries and their order.
    assert Enum.map(Timestamps.rows(entries, "raw"), &elem(&1, 0)) == entries
  end

  test "header mode recognizes string keys and nested headers without repeating boundaries" do
    entries =
      entries([{:head, 0}, {:text, 1}, {:head, 3}, {:text, 5}, {:head, 7}])
      |> Enum.map(fn item ->
        entry = Map.new(item.entry, fn {key, value} -> {to_string(key), value} end)
        %{item | entry: Map.put(entry, "type", to_string(entry["type"]))}
      end)

    assert labels(entries, "diff_header") == ["0ms", nil, "3s", nil, "4s"]
  end

  test "header mode updates the last visible boundary when another part arrives" do
    first = entries([{:text, 0}, {:head, 1}, {:text, 2}])
    all = first ++ entries([{:text, 3}, {:head, 5}, {:text, 8}])

    assert labels(first, "diff_header") == ["0ms", "1s", "1s"]
    assert labels(all, "diff_header") == ["0ms", "1s", nil, nil, "4s", "3s"]

    assert labels(entries([{:text, 0}, {:text, 1}, {:text, 30}]), "diff_header") == [
             "0ms",
             nil,
             "30s"
           ]
  end

  test "Unix seconds, fractional seconds, DateTimes and ISO timestamps preserve millisecond differences" do
    entries =
      entries([
        {:text, 1_700_000_000},
        {:text, 1_700_000_000.3},
        {:text, ~U[2023-11-14 22:13:21.250Z]},
        {:text, "2023-11-15T00:13:22.500+02:00"}
      ])

    assert labels(entries, "diff") == ["0ms", "300ms", "950ms", "1s250ms"]
  end

  test "missing timestamps do not invent differences and backward timestamps remain signed" do
    entries =
      entries([{:text, 0}, {:text, nil}, {:text, 2}, {:head, "invalid"}, {:head, 5}, {:text, 4}])

    assert labels(entries, "diff") == ["0ms", "—", "—", "—", "—", "-1s"]
    assert labels(entries, "diff_header") == ["0ms", nil, nil, "—", "—", "-1s"]
  end

  test "empty and single-row traces work in every mode" do
    for mode <- ["raw", "diff", "diff_header"] do
      assert Timestamps.rows([], mode) == []
      assert length(Timestamps.rows(entries([{:text, 0}]), mode)) == 1
    end

    assert labels(entries([{:text, 0}]), "diff_header") == ["0ms"]
    assert labels(entries([{:text, nil}]), "diff_header") == ["—"]
  end

  defp entries(rows) do
    Enum.with_index(rows, fn {type, at}, index ->
      %{
        part: div(index, 3) + 1,
        row: rem(index, 3),
        entry: %{type: type, at: at, message: "row #{index}", level: index}
      }
    end)
  end

  defp labels(entries, mode), do: Enum.map(Timestamps.rows(entries, mode), &elem(&1, 2))
end
