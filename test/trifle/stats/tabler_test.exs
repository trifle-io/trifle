defmodule Trifle.Stats.TablerTest do
  use ExUnit.Case, async: true

  alias Trifle.Stats.Tabler

  defp dt(minute), do: DateTime.new!(~D[2026-01-01], Time.new!(12, minute, 0), "Etc/UTC")

  test "tabulize flattens nested values into sorted unique paths" do
    at = [dt(0), dt(1)]

    values = [
      %{"count" => 1, "pages" => %{"home" => 10}},
      %{"count" => 2, "pages" => %{"home" => 20, "about" => 5}}
    ]

    result = Tabler.tabulize(%{at: at, values: values})

    assert result.paths == ["count", "pages.about", "pages.home"]
    # :at is accumulated newest-first
    assert result.at == [dt(1), dt(0)]

    assert result.values == %{
             {"count", dt(0)} => 1,
             {"pages.home", dt(0)} => 10,
             {"count", dt(1)} => 2,
             {"pages.home", dt(1)} => 20,
             {"pages.about", dt(1)} => 5
           }
  end

  test "tabulize of an empty series" do
    assert Tabler.tabulize(%{at: [], values: []}) == %{at: [], paths: [], values: %{}}
  end

  test "seriesize builds chart rows per path from the table" do
    at = [dt(0), dt(1)]
    values = [%{"count" => 1}, %{"count" => 2}]

    result = Tabler.seriesize(%{at: at, values: values})

    assert %{"count" => rows} = result
    assert length(rows) == 2
    assert Enum.all?(rows, fn [ts, _v] -> is_integer(ts) end)
    assert Enum.map(rows, fn [_ts, v] -> v end) == [2, 1]
  end
end
