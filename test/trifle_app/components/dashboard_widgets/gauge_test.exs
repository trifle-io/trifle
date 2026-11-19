defmodule TrifleApp.Components.DashboardWidgets.GaugeTest do
  use ExUnit.Case, async: true
  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.{Gauge, Registry, WidgetData}

  defp stats do
    Series.new(%{
      at: [~U[2026-11-18 10:00:00Z], ~U[2026-11-18 11:00:00Z], ~U[2026-11-18 12:00:00Z]],
      values: [
        %{"duration" => %{"sum" => 900, "count" => 9}},
        %{"duration" => %{"sum" => 300, "count" => 1}},
        %{}
      ]
    })
  end

  defp widget do
    %{
      "id" => "g",
      "type" => "gauge",
      "unit" => "ms",
      "gauge_count_path" => "duration.count",
      "series" => [%{"kind" => "path", "path" => "duration.sum", "visible" => true}]
    }
  end

  test "weighted gauge travels through the registry and existing dataset transport" do
    maps = stats() |> WidgetData.datasets([widget()]) |> WidgetData.dataset_maps()
    payload = Registry.client_payload("gauge", "g", maps)
    assert payload.presentation == "gauge"
    assert payload.gauge.average == 120
    assert payload.gauge.latest == 300
    assert payload.gauge.unit == "ms"
  end

  test "normalized gauge types use the weighted dataset and canonical payload type" do
    for type <- ["Gauge", :gauge] do
      [payload] =
        stats()
        |> WidgetData.widget_payloads([Map.put(widget(), "type", type)])
        |> Map.values()

      assert payload.type == "gauge"
      assert payload.payload.presentation == "gauge"
      assert payload.payload.gauge.average == 120
      assert payload.payload.gauge.latest == 300
    end
  end

  test "normalized timeseries types retain the timeseries dataset branch" do
    for type <- ["timeseries", "Timeseries", :timeseries] do
      payload = WidgetData.widget_payloads(stats(), [Map.put(widget(), "type", type)])["g"]
      assert payload.type == "timeseries"
      assert payload.payload.presentation == "standard"
      assert length(payload.payload.series) == 1
      refute Map.has_key?(payload.payload, :gauge)
    end
  end

  defp wildcard_stats do
    Series.new(%{
      at: [~U[2026-11-18 10:00:00Z], ~U[2026-11-18 11:00:00Z]],
      values: [
        %{
          "workers" => %{
            "alpha" => %{"duration" => %{"count" => 50}},
            "beta" => %{"duration" => %{"sum" => 200, "count" => 4}},
            "gamma" => %{"duration" => %{"sum" => 300, "count" => 3}}
          },
          "count" => 20
        },
        %{
          "workers" => %{
            "alpha" => %{"duration" => %{"count" => 60}},
            "beta" => %{"duration" => %{"sum" => 60, "count" => 2}},
            "gamma" => %{"duration" => %{"sum" => 45, "count" => 3}}
          },
          "count" => 10
        }
      ]
    })
  end

  defp wildcard_widget do
    widget()
    |> Map.put("gauge_count_path", "workers.*.duration.count")
    |> Map.put("series", [
      %{"kind" => "path", "path" => "workers.*.duration.sum", "visible" => true}
    ])
  end

  test "wildcard counters match the selected numerator binding rather than the first counter" do
    payload = Gauge.dataset(wildcard_stats(), wildcard_widget())
    assert_in_delta payload.gauge.average, 260 / 6, 0.0001
    assert payload.gauge.latest == 30
  end

  test "exact scalar counters remain available for wildcard numerators" do
    payload =
      Gauge.dataset(wildcard_stats(), Map.put(wildcard_widget(), "gauge_count_path", "count"))

    assert_in_delta payload.gauge.average, 260 / 30, 0.0001
    assert payload.gauge.latest == 6
  end

  test "an unmatched wildcard counter never broadcasts to another numerator binding" do
    stats =
      Series.new(%{
        at: [~U[2026-11-18 10:00:00Z]],
        values: [
          %{
            "workers" => %{
              "alpha" => %{"duration" => %{"count" => 5}},
              "beta" => %{"duration" => %{"sum" => 200}}
            }
          }
        ]
      })

    payload = Gauge.dataset(stats, wildcard_widget())
    assert payload.gauge.average == nil
    assert payload.gauge.latest == nil
    assert payload.gauge.latest_at == nil
  end

  test "without counts averages populated numeric buckets" do
    payload = Gauge.dataset(stats(), Map.delete(widget(), "gauge_count_path"))
    assert payload.gauge.average == 600
    assert payload.gauge.latest == 300
  end

  test "missing count path does not silently use unweighted values" do
    payload = Gauge.dataset(stats(), Map.put(widget(), "gauge_count_path", "missing.count"))
    assert payload.gauge.average == nil
    assert payload.gauge.latest == nil
  end

  test "latest bucket ordering crosses calendar boundaries" do
    summary =
      Gauge.summarize([{~U[2026-10-31 23:00:00Z], 5, 1}, {~U[2026-11-01 00:00:00Z], 10, 1}])

    assert summary.latest == 10
    assert summary.latest_at == ~U[2026-11-01 00:00:00Z]
  end

  test "group-relative count paths follow expanded metric paths" do
    widget = widget() |> Map.put("gauge_count_path", "$.duration.count")

    assert Gauge.prefix_count_path(widget, "workers.one")["gauge_count_path"] ==
             "workers.one.duration.count"

    assert Gauge.prefix_count_path(widget(), "workers.one")["gauge_count_path"] ==
             "duration.count"
  end

  test "summary excludes missing, zero count and preserves measured zeros" do
    assert Gauge.summarize([{1, nil, 1}, {2, 3, 0}, {3, Decimal.new(0), Decimal.new(2)}]) == %{
             average: 0.0,
             latest: 0.0,
             latest_at: 3
           }
  end
end
