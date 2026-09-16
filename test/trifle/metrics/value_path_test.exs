defmodule Trifle.Metrics.ValuePathTest do
  use ExUnit.Case, async: true
  alias Trifle.Metrics.{Query, ValuePath}
  alias Trifle.Stats.{Packer, Series, Tabler}
  alias TrifleApp.Components.DashboardWidgets.{GroupExpansion, Table}

  @at ~U[2026-01-01 00:00:00Z]
  @values %{
    "jobs" => %{
      "test.rb" => %{"count" => 2},
      "test" => %{"rb" => %{"count" => 3}},
      "*" => %{"count" => 5}
    }
  }

  test "library storage output yields distinct app paths and literal-star selectors" do
    input = %{~S(jobs.test\.rb.count) => 2, "jobs.test.rb.count" => 3, ~S(jobs.\*.count) => 5}
    assert Packer.unpack(Packer.pack(input)) == @values
    series = %Series{series: %{at: [@at], values: [@values]}}
    assert Query.available_paths(series) == Enum.sort(Map.keys(input))
    assert Tabler.tabulize(series.series).paths == Enum.sort(Map.keys(input))
    assert {:ok, ~S(jobs.\*.count)} = Query.ensure_no_wildcards(~S(jobs.\*.count))
    assert {:error, _} = Query.ensure_no_wildcards("jobs.*.count")
  end

  test "captures are based on segments and preserve concrete selector identity" do
    assert ValuePath.captures("jobs.*.count", ~S(jobs.test\.rb.count)) == {:ok, [~S(test\.rb)]}
    assert ValuePath.captures("jobs.*.count", ~S(jobs.\*.count)) == {:ok, [~S(\*)]}
    assert ValuePath.captures(~S(jobs.\*.count), ~S(jobs.\*.count)) == {:ok, []}
    assert ValuePath.captures(~S(jobs.\*.count), "jobs.test.count") == :error
    refute ValuePath.prefix?(~S(jobs.test\.rb.count), "jobs.test")
    assert ValuePath.strip_wildcard(~S(jobs.\*)) == ~S(jobs.\*)
    assert ValuePath.strip_wildcard(~S(jobs.test\.rb.*)) == ~S(jobs.test\.rb)
  end

  test "table glob matching only expands unescaped stars" do
    assert ValuePath.glob_matches?(~S(jobs.test\.rb.count), "jobs.*.count")
    assert ValuePath.glob_matches?(~S(jobs.\*.count), ~S(jobs.\*.count))
    refute ValuePath.glob_matches?("jobs.test.count", ~S(jobs.\*.count))
    assert ValuePath.glob_matches?(~S(jobs.test\*rb.count), ~S(jobs.test\*r*.count))
    refute ValuePath.glob_matches?("jobs.testXrb.count", ~S(jobs.test\*r*.count))
  end

  test "table filtering and display trimming preserve literal dotted and star fields" do
    series = %Series{series: %{at: [@at], values: [@values], granularity: "1h"}}

    for {path, count} <- [{~S(jobs.test\.rb), 2}, {~S(jobs.\*), 5}] do
      widget = %{"id" => "escaped", "type" => "table", "paths" => [path]}
      dataset = Table.dataset(series, widget)
      assert [row] = dataset.rows
      assert row.display_path == "count"
      assert dataset.values[{row.path, @at}] == count
    end
  end

  test "wildcard group expansion keeps dotted jobs and literal-star groups selectable" do
    series = %Series{series: %{at: [@at], values: [@values]}}

    group = %{
      "id" => "jobs",
      "type" => "group",
      "group_path" => "jobs.*",
      "children" => [
        %{
          "id" => "count",
          "type" => "timeseries",
          "series" => [%{"kind" => "nested", "path" => "count", "visible" => true}]
        }
      ]
    }

    expanded = GroupExpansion.expand_root_items([group], series)
    assert Enum.any?(expanded, &String.ends_with?(&1["title"], "jobs.test.rb"))
    refute Enum.any?(expanded, &String.contains?(&1["title"], ~S(\.)))
    paths = Enum.map(expanded, fn g -> hd(hd(g["children"])["series"])["path"] end)

    assert Enum.sort(paths) ==
             Enum.sort([~S(jobs.\*.count), "jobs.test.count", ~S(jobs.test\.rb.count)])

    assert GroupExpansion.valid_group_path?(~S(jobs.\*))
    refute GroupExpansion.terminal_wildcard?(~S(jobs.\*))
    assert GroupExpansion.terminal_wildcard?(~S(jobs.\*.*))
  end

  test "Explore renders decoded labels but never leaks storage percent encoding" do
    path = ~S(jobs.Trifle\.Monitors\.Jobs\.DispatchRunner.count)

    html =
      path
      |> TrifleApp.ExploreCore.format_nested_path([path], %{})
      |> Phoenix.HTML.safe_to_string()

    assert html =~ "Trifle.Monitors.Jobs.DispatchRunner"
    refute html =~ "%2E"
    refute html =~ ~S(Trifle\.Monitors)
  end
end
