defmodule Trifle.Traces.OverviewTest do
  use ExUnit.Case, async: true
  alias Trifle.Traces.Overview

  defp input do
    at = [1000, 2000, 3000]

    values = [
      %{
        "count" => 9,
        "states" => %{"success" => 8, "error" => 1},
        "duration" => %{
          "sum" => 900,
          "count" => 9,
          "states" => %{"error" => %{"sum" => 100, "count" => 1}}
        },
        "entries" => %{"count" => 90}
      },
      %{
        "count" => 1,
        "states" => %{"success" => 1},
        "duration" => %{"sum" => 300, "count" => 1},
        "entries" => %{"count" => 0}
      },
      %{}
    ]

    %{
      catalog: %{
        at: at,
        values: [%{"keys" => %{"jobs/a" => 9}}, %{"keys" => %{"jobs/a" => 1}}, %{}]
      },
      metrics: %{"jobs/a" => %{at: at, values: values}}
    }
  end

  test "uses weighted averages and latest populated bucket, preserving zero lines" do
    assert %{rows: [row]} = Overview.build(input(), "jobs", nil, %{})
    assert row.count == 10
    assert row.success == 90
    assert row.success_rate == %{average: 90.0, latest: 100.0, latest_at: 2000}

    assert row.state_distribution == [
             %{state: "success", count: 9, percentage: 90.0},
             %{state: "error", count: 1, percentage: 10.0}
           ]

    assert row.duration == %{average: 120.0, latest: 300.0, latest_at: 2000}
    assert row.lines == %{average: 9.0, latest: 0.0, latest_at: 2000}
  end

  test "state filters count and duration, with all-state success and unavailable lines" do
    assert %{rows: [row]} = Overview.build(input(), "jobs", "error", %{})
    assert row.count == 1
    assert row.success == 90
    assert row.success_rate == %{average: 90.0, latest: 100.0, latest_at: 2000}

    assert %{rows: [unfiltered]} = Overview.build(input(), "jobs", nil, %{})
    assert row.state_distribution == unfiltered.state_distribution

    assert row.duration.average == 100
    assert row.lines.average == nil
    assert Enum.map(row.series, & &1.state) == ["error"]
    assert Overview.build(input(), "jobs", "running", %{}).rows == []
  end

  test "expanded points retain raw measurements, zero values and empty buckets" do
    %{rows: [row]} = Overview.build(input(), "jobs", nil, %{})
    [first, second, empty] = row.points
    assert first.at == 1000
    assert first.states == %{"success" => 8, "error" => 1}
    assert first.count == 9
    assert first.duration_sum == 900
    assert first.duration_count == 9
    assert first.duration == 100
    assert first.lines_sum == 90
    assert first.lines == 10
    assert second.lines == 0
    assert empty.count == 0
    assert empty.duration == nil
    assert empty.lines == nil
    assert empty.success == nil

    %{rows: [filtered]} = Overview.build(input(), "jobs", "error", %{})
    assert hd(filtered.points).count == 1
    assert hd(filtered.points).total_count == 9
    assert hd(filtered.points).duration_sum == 100
    assert hd(filtered.points).duration_count == 1
    assert hd(filtered.points).lines == nil
    assert hd(filtered.points).lines_sum == 90
  end

  test "cached summaries omit expanded points and can be paginated independently" do
    activity = Trifle.Traces.Activity.build(input())
    [row] = rows = Overview.prepare(input(), nil, nil, activity)
    refute Map.has_key?(row, :points)
    assert Overview.paginate(rows, %{"jobs_size" => "3"}).rows == rows
    assert Overview.expand(row, input(), nil, activity).points != []
    collapsed = Overview.collapsed(input(), nil, nil, %{"jobs_collapsed" => "true"}, activity)
    assert collapsed.rows == []
    assert collapsed.total == 1
  end

  test "matches exact and child paths on segment boundaries without parent rollups" do
    base = input()
    metric = base.metrics["jobs/a"]
    base = %{base | metrics: Map.new(["jobs/a", "jobs/a/b", "jobs/ab"], &{&1, metric})}

    assert Enum.map(Overview.build(base, "jobs/a", nil, %{}).rows, & &1.path) == [
             "jobs/a",
             "jobs/a/b"
           ]
  end

  test "state distribution keeps unclassified traces and handles jobs with no traces" do
    base = input()

    metrics = %{
      "jobs/legacy" => %{at: [1000], values: [%{"count" => 4}]},
      "jobs/empty" => %{at: [1000], values: [%{}]}
    }

    rows = Overview.build(%{base | metrics: metrics}, nil, nil, %{}).rows
    legacy = Enum.find(rows, &(&1.path == "jobs/legacy"))
    empty = Enum.find(rows, &(&1.path == "jobs/empty"))
    assert legacy.success == 0
    assert legacy.state_distribution == [%{state: "unclassified", count: 4, percentage: 100.0}]
    assert empty.success == nil
    assert empty.state_distribution == []
  end

  test "sorts globally before pagination, breaking ties by path and placing missing values last" do
    base = input()
    metric = base.metrics["jobs/a"]

    metrics =
      Map.new(1..30, fn n -> {"jobs/#{String.pad_leading(to_string(n), 2, "0")}", metric} end)

    base = %{
      base
      | metrics: Map.put(metrics, "jobs/missing", %{at: [1000], values: [%{"count" => 1}]}),
        catalog: %{at: [1000, 2000, 3000], values: [%{}, %{}, %{}]}
    }

    page = Overview.build(base, nil, nil, %{"jobs_sort" => "duration", "jobs_page" => "2"})
    assert page.total == 31
    assert page.pages == 4
    assert hd(page.rows).path == "jobs/10"
    last = Overview.build(base, nil, nil, %{"jobs_sort" => "duration", "jobs_page" => "99"})
    assert last.page == 4
    assert List.last(last.rows).path == "jobs/missing"
  end

  test "empty input and malformed controls are safe" do
    page =
      Overview.build(nil, nil, nil, %{
        "jobs_size" => "9999",
        "jobs_page" => "-1",
        "jobs_sort" => "bad"
      })

    assert page.rows == []
    assert page.size == 9
    assert page.page == 1
    assert page.sort == "count"
  end
end
