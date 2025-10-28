defmodule Trifle.Monitors.AlertEvaluatorTest do
  use Trifle.DataCase, async: true

  alias Trifle.Monitors.Alert
  alias Trifle.Monitors.Alert.Settings
  alias Trifle.Monitors.AlertEvaluator
  alias Trifle.Stats.Series

  describe "evaluate/4 for threshold alerts" do
    test "flags latest breach and builds overlay" do
      alert =
        %Alert{
          id: "alert-threshold",
          analysis_strategy: :threshold,
          settings: %Settings{
            threshold_direction: :above,
            threshold_value: 110.0
          }
        }

      series =
        build_series([100.0, 105.0, 120.0])

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric")

      assert result.triggered?
      assert [%{} | _] = result.segments
      overlay = AlertEvaluator.overlay(result)
      assert overlay.triggered
      assert length(overlay.segments) == 1
      assert match?(%{alert_id: _, strategy: :threshold}, overlay)
    end
  end

  describe "evaluate/4 for range alerts" do
    test "detects out-of-range values" do
      alert =
        %Alert{
          id: "alert-range",
          analysis_strategy: :range,
          settings: %Settings{
            range_min_value: 50.0,
            range_max_value: 80.0
          }
        }

      series = build_series([60.0, 82.0, 78.0])

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric")

      assert result.triggered?
      assert [%{} | _] = result.segments

      overlay = AlertEvaluator.overlay(result)
      assert overlay.triggered
      assert length(overlay.reference_lines) == 2
      assert length(overlay.bands) == 1
    end
  end

  describe "evaluate/4 for Hampel alerts" do
    test "flags robust outliers" do
      alert =
        %Alert{
          id: "alert-hampel",
          analysis_strategy: :hampel,
          settings: %Settings{
            hampel_window_size: 3,
            hampel_k: 3.0,
            hampel_mad_floor: 0.1
          }
        }

      series = build_series([10.0, 10.2, 9.9, 30.0])

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric")

      assert result.triggered?
      assert [] == result.segments
      assert [%{} | _] = result.points

      overlay = AlertEvaluator.overlay(result)
      assert overlay.triggered
      assert length(overlay.points) == 1
    end

    test "ignores nil datapoints" do
      alert =
        %Alert{
          id: "alert-hampel-nil",
          analysis_strategy: :hampel,
          settings: %Settings{
            hampel_window_size: 3,
            hampel_k: 2.5,
            hampel_mad_floor: 0.1
          }
        }

      series = build_series([10.0, nil, 11.0, 12.0, 45.0])

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric")

      assert result.triggered?
      assert Enum.any?(result.points, &match?(%{index: _}, &1))
    end
  end

  describe "evaluate/4 for CUSUM alerts" do
    test "captures sustained shifts" do
      alert =
        %Alert{
          id: "alert-cusum",
          analysis_strategy: :cusum,
          settings: %Settings{
            cusum_k: 0.5,
            cusum_h: 2.0
          }
        }

      series = build_series([10.0, 10.5, 11.0, 15.0, 18.0, 19.5])

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric")

      assert result.triggered?
      assert [%{} | _] = result.segments

      overlay = AlertEvaluator.overlay(result)
      assert overlay.triggered
      assert length(overlay.segments) >= 1
    end

    test "handles missing datapoints" do
      alert =
        %Alert{
          id: "alert-cusum-nil",
          analysis_strategy: :cusum,
          settings: %Settings{
            cusum_k: 0.5,
            cusum_h: 1.5
          }
        }

      series = build_series([10.0, nil, 12.0, 11.5, nil, 16.0])

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric")
      assert is_boolean(result.triggered?)
      overlay = AlertEvaluator.overlay(result)
      assert is_map(overlay)
    end
  end

  defp build_series(values) when is_list(values) do
    base_time = ~U[2025-01-01 00:00:00Z]

    raw = %{
      at:
        values
        |> Enum.with_index()
        |> Enum.map(fn {_value, idx} -> DateTime.add(base_time, idx * 60, :second) end),
      values: Enum.map(values, fn value -> %{"metric" => value} end)
    }

    Series.new(raw)
  end
end
