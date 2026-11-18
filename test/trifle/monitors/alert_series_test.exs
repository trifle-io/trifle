defmodule Trifle.Monitors.AlertSeriesTest do
  use ExUnit.Case, async: true

  alias Trifle.Monitors.{Alert, AlertEvaluator, AlertSeries}
  alias Trifle.Monitors.Alert.Settings
  alias Trifle.Monitors.Monitor
  alias Trifle.Stats.Series

  test "normalize_rows_params reads bracketed series params" do
    params = %{
      "alert_series_kind[]" => ["path", "expression"],
      "alert_series_path[]" => ["orders", ""],
      "alert_series_expression[]" => ["", "a / 2"],
      "alert_series_label[]" => ["Orders", "Half orders"],
      "alert_series_visible[]" => ["true", "false"],
      "alert_series_color_selector[]" => ["default.*", "default.*"]
    }

    rows = AlertSeries.normalize_rows_params(params, "alert_series", ensure_default: false)

    assert [
             %{"kind" => "path", "path" => "orders", "label" => "Orders", "visible" => true},
             %{
               "kind" => "expression",
               "expression" => "a / 2",
               "label" => "Half orders",
               "visible" => false
             }
           ] = Enum.map(rows, &Map.take(&1, ["kind", "path", "expression", "label", "visible"]))
  end

  test "normalize_attrs falls back to legacy metric path when row params have no final row" do
    attrs = %{
      "alert_series_kind[]" => [""],
      "alert_series_path[]" => [""],
      "alert_series_expression[]" => [""],
      "alert_series_label[]" => [""],
      "alert_series_visible[]" => ["true"],
      "alert_series_color_selector[]" => ["default.*"],
      "alert_metric_path" => "orders"
    }

    normalized = AlertSeries.normalize_attrs(attrs)

    assert normalized["alert_metric_path"] == "orders"
    assert [%{"kind" => "path", "path" => "orders"}] = normalized["alert_series"]
  end

  test "rows fall back to legacy metric path when stored alert_series has no final row" do
    monitor = %Monitor{
      id: "monitor-1",
      alert_metric_key: "sales",
      alert_metric_path: "orders",
      alert_series: [%{"kind" => "path", "path" => "", "visible" => true}]
    }

    assert [%{"kind" => "path", "path" => "orders"}] = AlertSeries.rows(monitor)
  end

  test "resolved_final_targets preserves missing buckets for charts and evaluation" do
    base_time = ~U[2025-01-01 00:00:00Z]

    stats =
      Series.new(%{
        at: [
          base_time,
          DateTime.add(base_time, 60, :second),
          DateTime.add(base_time, 120, :second)
        ],
        values: [
          %{"orders" => 10.0},
          %{"orders" => nil},
          %{"orders" => 14.0}
        ]
      })

    monitor = %Monitor{
      id: "monitor-1",
      alert_metric_key: "sales",
      alert_series: [%{"kind" => "path", "path" => "orders", "visible" => true}]
    }

    [target] = AlertSeries.resolved_final_targets(stats, monitor)

    assert Enum.map(target.points, & &1.value) == [10.0, nil, 14.0]
    assert Enum.map(target.data, fn [_ts, value] -> value end) == [10.0, nil, 14.0]
  end

  describe "missing bucket evaluation" do
    test "excludes the unfinished bucket and zero-fills the latest completed bucket" do
      stats = build_series([150.0, 50.0, nil, nil])
      [target] = AlertSeries.resolved_final_targets(stats, monitor())

      for fill <- [false, true] do
        alert = threshold_alert(:above, 100.0, fill)
        assert {:ok, result} = AlertEvaluator.evaluate_points(alert, "orders", target.points)

        refute result.triggered?
        assert result.latest_point.at == Enum.at(stats.series.at, 2)
        assert result.latest_point.value == if(fill, do: 0.0, else: nil)
      end

      assert Enum.map(target.data, &List.last/1) == [150.0, 50.0, nil, nil]
    end

    test "the missing-as-zero setting applies independently to each alert" do
      stats = build_series([20.0, nil, nil, nil])
      [target] = AlertSeries.resolved_final_targets(stats, monitor())

      for fill <- [false, true] do
        alert = threshold_alert(:below, 10.0, fill)
        assert {:ok, result} = AlertEvaluator.evaluate_points(alert, "orders", target.points)

        assert result.triggered? == fill
        assert result.meta.treat_nil_as_zero == fill
      end
    end

    test "a breach stops triggering once later completed buckets are missing" do
      alert = threshold_alert(:above, 100.0, true)

      for missing_buckets <- [1, 2, 30, 120, 239] do
        stats = build_series([150.0 | List.duplicate(nil, missing_buckets)])
        [target] = AlertSeries.resolved_final_targets(stats, monitor())

        assert {:ok, result} = AlertEvaluator.evaluate_points(alert, "orders", target.points)
        assert result.triggered? == (missing_buckets == 1)
        assert result.latest_point.at == Enum.at(stats.series.at, -2)
      end
    end

    test "fully missing paths and chained formulas still reach zero-fill" do
      for values <- [List.duplicate(nil, 4), List.duplicate(:absent, 4)],
          rows <- [
            [%{"kind" => "path", "path" => "orders"}],
            [
              %{"kind" => "path", "path" => "orders", "visible" => false},
              %{"kind" => "expression", "expression" => "a * 2", "visible" => false},
              %{"kind" => "expression", "expression" => "b + 1"}
            ]
          ] do
        stats = build_series(values)
        [target] = AlertSeries.resolved_final_targets(stats, %{monitor() | alert_series: rows})

        assert Enum.map(target.points, & &1.value) == [nil, nil, nil, nil]

        alert = threshold_alert(:below, 10.0, true)

        assert {:ok, result} =
                 AlertEvaluator.evaluate_points(alert, target.source_path, target.points)

        assert result.triggered?
        assert result.latest_point.value == 0.0
      end
    end

    test "range alerts evaluate missing completed buckets as zero when enabled" do
      stats = build_series([60.0, nil, nil, nil])
      [target] = AlertSeries.resolved_final_targets(stats, monitor())

      for fill <- [false, true] do
        alert = %Alert{
          analysis_strategy: :range,
          settings: %Settings{
            range_min_value: 50.0,
            range_max_value: 80.0,
            treat_nil_as_zero: fill
          }
        }

        assert {:ok, result} = AlertEvaluator.evaluate_points(alert, "orders", target.points)
        assert result.triggered? == fill
      end
    end
  end

  test "monitor source formulas can smooth a hidden source before alert evaluation" do
    stats =
      Series.new(%{
        at: Enum.map(0..2, &DateTime.add(~U[2025-01-01 00:00:00Z], &1 * 60, :second)),
        values: [%{"orders" => 10}, %{"orders" => 20}, %{"orders" => 30}]
      })

    monitor = %Monitor{
      id: "monitor-smoothing",
      alert_metric_key: "sales",
      alert_series: [
        %{"kind" => "path", "path" => "orders", "visible" => false},
        %{"kind" => "expression", "expression" => "moving_avg(a, 2)", "label" => "Average"}
      ]
    }

    [target] = AlertSeries.resolved_final_targets(stats, monitor)
    assert Enum.map(target.points, & &1.value) == [10, 15, 25]
  end

  defp monitor do
    %Monitor{
      id: "monitor-missing",
      alert_metric_key: "sales",
      alert_timeframe: "4h",
      alert_granularity: "1m",
      alert_series: [%{"kind" => "path", "path" => "orders", "visible" => true}]
    }
  end

  defp threshold_alert(direction, threshold, fill) do
    %Alert{
      analysis_strategy: :threshold,
      settings: %Settings{
        threshold_direction: direction,
        threshold_value: threshold,
        treat_nil_as_zero: fill
      }
    }
  end

  defp build_series(values) do
    Series.new(%{
      at:
        values
        |> Enum.with_index()
        |> Enum.map(fn {_, index} ->
          DateTime.add(~U[2025-01-01 00:00:00Z], index * 60, :second)
        end),
      values:
        Enum.map(values, fn
          :absent -> %{}
          value -> %{"orders" => value}
        end)
    })
  end
end
