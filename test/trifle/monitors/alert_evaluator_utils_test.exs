defmodule Trifle.Monitors.AlertEvaluator.UtilsTest do
  use ExUnit.Case, async: true

  alias Trifle.Monitors.AlertEvaluator
  alias Trifle.Monitors.AlertEvaluator.Utils, as: AlertEvaluatorUtils

  test "build_series_aggregation preserves base meta and summarizes mixed results" do
    results = [
      %{
        target: %{name: "delta: a", source_path: "delta.a"},
        result: %AlertEvaluator.Result{
          path: "delta.a",
          triggered?: false,
          summary: "No recent breaches detected.",
          meta: %{baseline: true}
        }
      },
      %{
        target: %{name: "delta: b", source_path: "delta.b"},
        result: %AlertEvaluator.Result{
          path: "delta.b",
          triggered?: true,
          summary: "Threshold breached.",
          meta: %{marker: "critical"}
        }
      },
      %{
        target: %{name: "delta: c", source_path: "delta.c"},
        error: :no_data
      }
    ]

    result =
      AlertEvaluatorUtils.build_series_aggregation(
        results,
        alert_id: "alert-1",
        strategy: :threshold
      )

    assert result.alert_id == "alert-1"
    assert result.strategy == :threshold
    assert result.path == "delta.b"
    assert result.triggered?
    assert result.summary == "delta: b: Threshold breached."
    assert result.meta[:marker] == "critical"
    assert result.meta[:series_count] == 3

    assert [
             %{name: "delta: a", triggered: false, source_path: "delta.a"},
             %{name: "delta: b", triggered: true, source_path: "delta.b"}
           ] =
             Enum.map(
               result.meta[:series_results],
               &Map.take(&1, [:name, :triggered, :source_path])
             )

    assert [%{name: "delta: c", source_path: "delta.c", error: :no_data}] =
             result.meta[:series_errors]
  end
end
