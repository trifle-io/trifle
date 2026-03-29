defmodule TrifleApp.Exports.MonitorLayoutTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Trifle.Monitors.Alert
  alias Trifle.Monitors.Alert.Settings
  alias Trifle.Monitors.Monitor
  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.WidgetData
  alias TrifleApp.Exports.MonitorLayout

  test "builds per-series alert groups from the final resolved series row" do
    stats = build_series()

    monitor = %Monitor{
      id: "monitor-1",
      type: :alert,
      name: "Latency guard",
      alert_metric_key: "latency.p95",
      alert_series: [
        %{"kind" => "path", "path" => "incoming.*", "visible" => false},
        %{"kind" => "path", "path" => "outgoing.*", "visible" => false},
        %{"kind" => "expression", "expression" => "a - b", "label" => "delta", "visible" => true}
      ],
      alerts: [
        %Alert{
          id: "warning",
          analysis_strategy: :threshold,
          settings: %Settings{threshold_direction: :above, threshold_value: 6.0}
        },
        %Alert{
          id: "critical",
          analysis_strategy: :threshold,
          settings: %Settings{threshold_direction: :above, threshold_value: 12.0}
        }
      ]
    }

    dashboard = MonitorLayout.alert_dashboard(monitor, stats)
    [source_widget | groups] = get_in(dashboard, [:payload, "grid"])

    assert source_widget["id"] == "#{monitor.id}-alert-source"
    assert length(groups) == 2
    assert Enum.all?(groups, &(&1["type"] == "group"))
    assert Enum.all?(groups, &(length(&1["children"]) == 2))

    datasets =
      stats
      |> WidgetData.datasets_from_dashboard(dashboard)
      |> WidgetData.dataset_maps()
      |> then(fn maps -> MonitorLayout.inject_alert_overlay(maps, monitor, stats) end)
      |> elem(0)

    series_a_widget_id = "#{monitor.id}-alert-series-0-alert-warning-chart"
    series_b_widget_id = "#{monitor.id}-alert-series-1-alert-critical-chart"

    assert %{series: [%{name: name_a}]} = datasets.timeseries[series_a_widget_id]
    assert %{series: [%{name: name_b}]} = datasets.timeseries[series_b_widget_id]
    assert name_a == "delta: a"
    assert name_b == "delta: b"
  end

  test "inject_alert_overlay limits evaluation to rendered alert widgets when ids are provided" do
    stats = build_series()

    monitor = %Monitor{
      id: "monitor-1",
      type: :alert,
      name: "Latency guard",
      alert_metric_key: "latency.p95",
      alert_series: [
        %{"kind" => "path", "path" => "incoming.*", "visible" => false},
        %{"kind" => "path", "path" => "outgoing.*", "visible" => false},
        %{"kind" => "expression", "expression" => "a - b", "label" => "delta", "visible" => true}
      ],
      alerts: [
        %Alert{
          id: "warning",
          analysis_strategy: :threshold,
          settings: %Settings{threshold_direction: :above, threshold_value: 6.0}
        },
        %Alert{
          id: "critical",
          analysis_strategy: :threshold,
          settings: %Settings{threshold_direction: :above, threshold_value: 12.0}
        }
      ]
    }

    dashboard = MonitorLayout.alert_dashboard(monitor, stats)

    datasets =
      stats
      |> WidgetData.datasets_from_dashboard(dashboard)
      |> WidgetData.dataset_maps()

    warning_widget_id = "#{monitor.id}-alert-series-0-alert-warning-chart"
    critical_widget_id = "#{monitor.id}-alert-series-0-alert-critical-chart"

    {datasets, evaluations} =
      MonitorLayout.inject_alert_overlay(datasets, monitor, stats, [warning_widget_id])

    assert datasets.timeseries[warning_widget_id].alert_summary
    refute Map.has_key?(evaluations, "critical")
    assert Map.has_key?(evaluations, "warning")
    refute Map.has_key?(datasets.timeseries[critical_widget_id], :alert_summary)
  end

  test "inject_alert_overlay preserves trailing chart gaps for alert widgets" do
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
      type: :alert,
      name: "Sales tracking",
      alert_metric_key: "sales",
      alert_series: [%{"kind" => "path", "path" => "orders", "visible" => true}],
      alerts: [
        %Alert{
          id: "warning",
          analysis_strategy: :threshold,
          settings: %Settings{threshold_direction: :above, threshold_value: 6.0}
        }
      ]
    }

    dashboard = MonitorLayout.alert_dashboard(monitor, stats)

    datasets =
      stats
      |> WidgetData.datasets_from_dashboard(dashboard)
      |> WidgetData.dataset_maps()
      |> then(fn maps -> MonitorLayout.inject_alert_overlay(maps, monitor, stats) end)
      |> elem(0)

    widget_id = "#{monitor.id}-alert-series-0-alert-warning-chart"

    assert %{series: [%{data: data}]} = datasets.timeseries[widget_id]
    assert Enum.map(data, fn [_ts, value] -> value end) == [10.0, nil, 14.0]
  end

  test "alert_dashboard logs and skips widget groups when stats are missing" do
    monitor = %Monitor{
      id: "monitor-1",
      type: :alert,
      name: "Latency guard",
      alert_metric_key: "latency.p95",
      alert_series: [%{"kind" => "path", "path" => "incoming.*", "visible" => true}],
      alerts: [
        %Alert{
          id: "warning",
          analysis_strategy: :threshold,
          settings: %Settings{threshold_direction: :above, threshold_value: 6.0}
        }
      ]
    }

    log =
      capture_log(fn ->
        dashboard = MonitorLayout.alert_dashboard(monitor, nil)
        assert length(get_in(dashboard, [:payload, "grid"])) == 1
      end)

    assert log =~ "Skipping alert widget groups"
  end

  defp build_series do
    base_time = ~U[2025-01-01 00:00:00Z]

    raw = %{
      at: [
        base_time,
        DateTime.add(base_time, 60, :second),
        DateTime.add(base_time, 120, :second)
      ],
      values: [
        %{
          "incoming" => %{"a" => 10.0, "b" => 16.0},
          "outgoing" => %{"a" => 3.0, "b" => 4.0}
        },
        %{
          "incoming" => %{"a" => 12.0, "b" => 18.0},
          "outgoing" => %{"a" => 5.0, "b" => 6.0}
        },
        %{
          "incoming" => %{"a" => 15.0, "b" => 22.0},
          "outgoing" => %{"a" => 7.0, "b" => 8.0}
        }
      ]
    }

    Series.new(raw)
  end
end
