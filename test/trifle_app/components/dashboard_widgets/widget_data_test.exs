defmodule TrifleApp.Components.DashboardWidgets.WidgetDataTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.WidgetData

  @grid_items [
    %{"id" => "kpi-1", "type" => "kpi", "path" => "metrics.count", "function" => "mean", "timeseries" => true},
    %{"id" => "ts-1", "type" => "timeseries", "paths" => ["metrics.count"], "chart_type" => "line"},
    %{"id" => "cat-1", "type" => "category", "paths" => ["metrics.category"], "chart_type" => "bar"},
    %{"id" => "text-1", "type" => "text", "title" => "Hello World"}
  ]

  setup do
    timestamps = [
      DateTime.from_naive!(~N[2024-01-01 00:00:00], "Etc/UTC"),
      DateTime.from_naive!(~N[2024-01-02 00:00:00], "Etc/UTC")
    ]

    values = [
      %{
        "metrics" => %{
          "count" => 5,
          "category" => %{"A" => 3, "B" => 2}
        }
      },
      %{
        "metrics" => %{
          "count" => 7,
          "category" => %{"A" => 4, "B" => 3}
        }
      }
    ]

    series = %Trifle.Stats.Series{
      series: %{
        at: timestamps,
        values: values
      }
    }

    %{series: series}
  end

  test "datasets returns data for each widget type", %{series: series} do
    dataset = WidgetData.datasets(series, @grid_items)

    assert [%{id: "kpi-1", value: value}] = dataset.kpi_values
    assert_in_delta value, 6.0, 0.001

    assert [%{id: "kpi-1", type: "sparkline", data: sparkline}] = dataset.kpi_visuals
    assert length(sparkline) == 2

    assert [%{id: "ts-1", series: ts_series}] = dataset.timeseries
    assert [%{name: "metrics.count", data: ts_points}] = ts_series
    assert length(ts_points) == 2

    assert [%{id: "cat-1", data: cat_data}] = dataset.category
    assert Enum.any?(cat_data, &(&1.name == "A"))
    assert Enum.any?(cat_data, &(&1.name == "B"))

    assert [%{id: "text-1", title: "Hello World"}] = dataset.text
  end

  test "dataset_maps indexes entries by widget id", %{series: series} do
    dataset_maps =
      series
      |> WidgetData.datasets(@grid_items)
      |> WidgetData.dataset_maps()

    assert %{"kpi-1" => %{value: value}} = dataset_maps.kpi_values
    assert_in_delta value, 6.0, 0.001

    assert %{"ts-1" => %{series: [_ | _]}} = dataset_maps.timeseries
    assert %{"cat-1" => %{data: cat_data}} = dataset_maps.category
    assert Enum.count(cat_data) >= 2
    assert %{"text-1" => %{title: "Hello World"}} = dataset_maps.text
  end

  test "datasets_from_dashboard delegates grid extraction", %{series: series} do
    dashboard = %{payload: %{"grid" => @grid_items}}

    direct = WidgetData.datasets(series, @grid_items)
    via_dashboard = WidgetData.datasets_from_dashboard(series, dashboard)

    assert direct == via_dashboard
  end

  test "datasets handles nil stats by still returning text widgets" do
    dataset = WidgetData.datasets(nil, @grid_items)

    assert dataset.kpi_values == []
    assert dataset.kpi_visuals == []
    assert dataset.timeseries == []
    assert dataset.category == []
    assert [%{id: "text-1"}] = dataset.text
  end
end
