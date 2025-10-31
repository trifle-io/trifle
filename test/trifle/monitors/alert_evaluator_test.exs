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

    test "optionally treats missing values as zero" do
      base_settings = %Settings{
        threshold_direction: :below,
        threshold_value: 10.0,
        treat_nil_as_zero: false
      }

      series = build_series([20.0, nil, nil, nil])

      alert_without_fill = %Alert{
        id: "alert-threshold-nil",
        analysis_strategy: :threshold,
        settings: base_settings
      }

      {:ok, result_without_fill} =
        AlertEvaluator.evaluate(alert_without_fill, series, "metric", exclude_recent: false)

      refute result_without_fill.triggered?
      refute result_without_fill.meta[:treat_nil_as_zero]

      alert_with_fill = %Alert{
        id: "alert-threshold-nil-fill",
        analysis_strategy: :threshold,
        settings: %{base_settings | treat_nil_as_zero: true}
      }

      {:ok, result_with_fill} =
        AlertEvaluator.evaluate(alert_with_fill, series, "metric", exclude_recent: false)

      assert result_with_fill.triggered?
      assert result_with_fill.meta[:treat_nil_as_zero]
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

    test "optionally treats missing values as zero" do
      base_settings = %Settings{
        range_min_value: 50.0,
        range_max_value: 80.0,
        treat_nil_as_zero: false
      }

      series = build_series([60.0, nil, nil, nil])

      alert_without_fill = %Alert{
        id: "alert-range-nil",
        analysis_strategy: :range,
        settings: base_settings
      }

      {:ok, result_without_fill} =
        AlertEvaluator.evaluate(alert_without_fill, series, "metric", exclude_recent: false)

      refute result_without_fill.triggered?
      refute result_without_fill.meta[:treat_nil_as_zero]

      alert_with_fill = %Alert{
        id: "alert-range-nil-fill",
        analysis_strategy: :range,
        settings: %{base_settings | treat_nil_as_zero: true}
      }

      {:ok, result_with_fill} =
        AlertEvaluator.evaluate(alert_with_fill, series, "metric", exclude_recent: false)

      assert result_with_fill.triggered?
      assert result_with_fill.meta[:treat_nil_as_zero]
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

    test "optionally treats missing values as zeros" do
      base_settings = %Settings{
        hampel_window_size: 3,
        hampel_k: 3.0,
        hampel_mad_floor: 0.1,
        treat_nil_as_zero: false
      }

      values = [200.0, 210.0, nil, nil, 0.0, 0.0, 0.0]
      series = build_series(values)

      alert_without_fill = %Alert{
        id: "alert-hampel-missing",
        analysis_strategy: :hampel,
        settings: base_settings
      }

      {:ok, result_without_fill} = AlertEvaluator.evaluate(alert_without_fill, series, "metric")
      refute result_without_fill.triggered?
      assert result_without_fill.points == []
      refute result_without_fill.meta[:treat_nil_as_zero]

      alert_with_fill = %Alert{
        id: "alert-hampel-missing-fill",
        analysis_strategy: :hampel,
        settings: %{base_settings | treat_nil_as_zero: true}
      }

      {:ok, result_with_fill} = AlertEvaluator.evaluate(alert_with_fill, series, "metric")
      assert result_with_fill.triggered?
      assert Enum.any?(result_with_fill.points, fn point -> match?(%{value: 0.0}, point) end)
      assert result_with_fill.meta[:treat_nil_as_zero]
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

    test "exposes treat missing configuration" do
      series = build_series([100.0, nil, nil, nil])

      alert =
        %Alert{
          id: "alert-cusum-nil",
          analysis_strategy: :cusum,
          settings: %Settings{
            cusum_k: 0.1,
            cusum_h: 0.5,
            treat_nil_as_zero: true
          }
        }

      {:ok, result} = AlertEvaluator.evaluate(alert, series, "metric", exclude_recent: false)
      assert result.meta[:treat_nil_as_zero]
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
