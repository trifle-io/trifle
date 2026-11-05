defmodule TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluatorTest do
  use ExUnit.Case, async: true

  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator

  defp stats do
    Series.new(%{
      at: Enum.map(0..2, &DateTime.add(~U[2025-01-01 00:00:00Z], &1 * 60, :second)),
      values: [
        %{"hosts" => %{"one" => 2, "two" => 20}},
        %{"hosts" => %{"one" => 4, "two" => nil}},
        %{"hosts" => %{"one" => 6, "two" => 60}}
      ]
    })
  end

  defp widget(type \\ "timeseries") do
    %{
      "type" => type,
      "series" => [
        %{"kind" => "path", "path" => "hosts.*", "visible" => false},
        %{"kind" => "expression", "expression" => "moving_avg(a, 2)", "visible" => false},
        %{"kind" => "expression", "expression" => "b * 10", "label" => "Smoothed"}
      ]
    }
  end

  test "hidden and chained formulas preserve independent wildcard bindings and labels" do
    rows = MetricSeriesEvaluator.resolve_timeline_rows(stats(), widget())
    series = MetricSeriesEvaluator.timeline_series(rows)
    assert Enum.map(series, & &1.name) == ["Smoothed: one", "Smoothed: two"]
    assert Enum.map(hd(series).data, &List.last/1) == [20, 30, 50]
    assert Enum.map(List.last(series).data, &List.last/1) == [200, nil, 600]

    aliased = Map.put(widget(), "series_aliases", %{"one" => "First host"})
    assert hd(MetricSeriesEvaluator.timeline_series(rows, aliased)).name == "Smoothed: First host"
  end

  test "KPI aggregation runs after the timeline transform" do
    rows = MetricSeriesEvaluator.resolve_kpi_scalar_rows(stats(), widget("kpi"), 1, "mean")
    entries = List.last(rows).entries |> Map.values() |> Enum.sort_by(& &1.name)
    assert Enum.map(entries, &Map.fetch!(&1.samples, 0)) == [100 / 3, 400]
  end

  test "a single reference broadcasts into each smoothed wildcard series" do
    widget = %{
      "type" => "timeseries",
      "series" => [
        %{"kind" => "path", "path" => "hosts.*", "visible" => false},
        %{"kind" => "path", "path" => "hosts.one", "visible" => false},
        %{"kind" => "expression", "expression" => "moving_avg(a, 2) / b", "label" => "Ratio"}
      ]
    }

    rows = MetricSeriesEvaluator.resolve_timeline_rows(stats(), widget)
    [one, two] = MetricSeriesEvaluator.timeline_series(rows)
    assert Enum.map(one.data, &List.last/1) == [1, 0.75, 5 / 6]
    assert Enum.map(two.data, &List.last/1) == [10, nil, 10]
  end

  test "category and distribution evaluation expose explicit formula errors" do
    [_, formula, _] = MetricSeriesEvaluator.resolve_category_rows(stats(), widget("category"))
    assert formula.entries == %{}
    assert formula.error.message =~ "requires timeline data"

    [_, formula, _] =
      MetricSeriesEvaluator.resolve_distribution_rows(
        stats(),
        widget("distribution"),
        "2d",
        [],
        [],
        1
      )

    assert formula.entries == %{}
    assert formula.error.message =~ "requires timeline data"
  end
end
