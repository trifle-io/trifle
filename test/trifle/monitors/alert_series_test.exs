defmodule Trifle.Monitors.AlertSeriesTest do
  use ExUnit.Case, async: true

  alias Trifle.Monitors.AlertSeries
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

  test "resolved_final_targets drops nil-valued points before evaluation data is built" do
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

    assert Enum.map(target.points, & &1.value) == [10.0, 14.0]
    assert Enum.map(target.data, fn [_ts, value] -> value end) == [10.0, 14.0]
  end
end
