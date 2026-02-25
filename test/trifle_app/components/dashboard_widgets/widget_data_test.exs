defmodule TrifleApp.Components.DashboardWidgets.WidgetDataTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.{Helpers, WidgetData, WidgetView}

  @grid_items [
    %{
      "id" => "kpi-1",
      "type" => "kpi",
      "path" => "metrics.count",
      "function" => "mean",
      "timeseries" => true
    },
    %{
      "id" => "ts-1",
      "type" => "timeseries",
      "paths" => ["metrics.count"],
      "chart_type" => "line"
    },
    %{
      "id" => "cat-1",
      "type" => "category",
      "paths" => ["metrics.category"],
      "chart_type" => "bar"
    },
    %{
      "id" => "table-1",
      "type" => "table",
      "paths" => ["metrics.table"],
      "title" => "Table View"
    },
    %{"id" => "text-1", "type" => "text", "title" => "Hello World"},
    %{
      "id" => "dist-1",
      "type" => "distribution",
      "title" => "Latency Buckets",
      "paths" => ["metrics.distribution.*"],
      "designator" => %{
        "type" => "custom",
        "buckets" => [10, 20]
      }
    }
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
          "category" => %{"A" => 3, "B" => 2},
          "table" => %{"payments" => %{"credit" => 4, "digital" => 6}},
          "distribution" => %{"10" => 2, "20" => 1}
        }
      },
      %{
        "metrics" => %{
          "count" => 7,
          "category" => %{"A" => 4, "B" => 3},
          "table" => %{"payments" => %{"credit" => 5, "digital" => 7}},
          "distribution" => %{"10" => 1, "20" => 2, "20+" => 1}
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
    assert Enum.any?(cat_data, &(&1.name == "metrics.category.A"))
    assert Enum.any?(cat_data, &(&1.name == "metrics.category.B"))
    assert [%{id: "table-1", rows: table_rows}] = dataset.table
    assert Enum.any?(table_rows, &(&1.display_path == "payments.credit"))

    assert [%{id: "text-1", title: "Hello World"}] = dataset.text

    assert [%{id: "dist-1", bucket_labels: buckets, series: dist_series}] = dataset.distribution
    assert buckets == ["10", "20", "20+"]
    assert [%{name: "metrics.distribution.*", values: values}] = dist_series
    assert Enum.any?(values, &(&1.bucket == "10" && &1.value > 0))
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
    assert %{"table-1" => %{rows: table_rows}} = dataset_maps.table
    assert is_list(table_rows)
    assert %{"text-1" => %{title: "Hello World"}} = dataset_maps.text

    assert %{"dist-1" => %{bucket_labels: ["10", "20", "20+"], series: [_ | _]}} =
             dataset_maps.distribution
  end

  test "datasets_from_dashboard delegates grid extraction", %{series: series} do
    dashboard = %{payload: %{"grid" => @grid_items}}

    direct = WidgetData.datasets(series, WidgetView.grid_items(dashboard))
    via_dashboard = WidgetData.datasets_from_dashboard(series, dashboard)

    assert direct == via_dashboard
  end

  test "datasets handles nil stats by still returning text widgets" do
    dataset = WidgetData.datasets(nil, @grid_items)

    assert dataset.kpi_values == []
    assert dataset.kpi_visuals == []
    assert dataset.timeseries == []
    assert dataset.category == []
    assert dataset.table == []
    assert [%{id: "text-1"}] = dataset.text
  end

  test "category datasets do not double count fallback path", %{series: series} do
    items = [
      %{
        "id" => "cat-dup",
        "type" => "category",
        "paths" => ["metrics.category"],
        "path" => "metrics.category",
        "chart_type" => "bar"
      }
    ]

    %{category: [%{data: data}]} = WidgetData.datasets(series, items)

    assert Enum.find(data, &(&1.name == "metrics.category.A")).value == 7.0
    assert Enum.find(data, &(&1.name == "metrics.category.B")).value == 5.0
  end

  test "timeseries wildcard selector with fixed index applies one color across emitted series", %{
    series: series
  } do
    items = [
      %{
        "id" => "ts-fixed",
        "type" => "timeseries",
        "paths" => ["metrics.category.*"],
        "path_inputs" => ["metrics.category.*"],
        "series_color_selectors" => %{"metrics.category.*" => "default.4"},
        "chart_type" => "line"
      }
    ]

    %{timeseries: [%{series: dataset_series}]} = WidgetData.datasets(series, items)

    assert length(dataset_series) >= 2

    assert Enum.uniq(Enum.map(dataset_series, & &1.color)) == [
             Helpers.resolve_series_color("default.4", 0)
           ]
  end

  test "category wildcard selector with fixed index applies one color across categories", %{
    series: series
  } do
    items = [
      %{
        "id" => "cat-fixed",
        "type" => "category",
        "paths" => ["metrics.category.*"],
        "path_inputs" => ["metrics.category.*"],
        "series_color_selectors" => %{"metrics.category.*" => "default.2"},
        "chart_type" => "bar"
      }
    ]

    %{category: [%{data: data}]} = WidgetData.datasets(series, items)
    assert length(data) >= 2
    assert Enum.uniq(Enum.map(data, & &1.color)) == [Helpers.resolve_series_color("default.2", 0)]
  end

  test "category wildcard selector with palette rotation rotates colors per emitted category", %{
    series: series
  } do
    items = [
      %{
        "id" => "cat-rotate",
        "type" => "category",
        "paths" => ["metrics.category.*"],
        "path_inputs" => ["metrics.category.*"],
        "series_color_selectors" => %{"metrics.category.*" => "default.*"},
        "chart_type" => "bar"
      }
    ]

    %{category: [%{data: data}]} = WidgetData.datasets(series, items)
    assert length(data) >= 2

    colors = Enum.map(data, & &1.color)
    assert length(Enum.uniq(colors)) >= 2
  end

  test "distribution selectors apply per configured path", %{series: series} do
    items = [
      %{
        "id" => "dist-colors",
        "type" => "distribution",
        "paths" => ["metrics.distribution.*", "metrics.other.*"],
        "path_inputs" => ["metrics.distribution.*", "metrics.other.*"],
        "series_color_selectors" => %{
          "metrics.distribution.*" => "default.0",
          "metrics.other.*" => "default.6"
        },
        "designator" => %{
          "type" => "custom",
          "buckets" => [10, 20]
        }
      }
    ]

    %{distribution: [%{series: dist_series}]} = WidgetData.datasets(series, items)

    assert Enum.any?(dist_series, &(&1.path == "metrics.distribution.*"))
    assert Enum.any?(dist_series, &(&1.path == "metrics.other.*"))

    assert Enum.find(dist_series, &(&1.path == "metrics.distribution.*")).color ==
             Helpers.resolve_series_color("default.0", 0)

    assert Enum.find(dist_series, &(&1.path == "metrics.other.*")).color ==
             Helpers.resolve_series_color("default.6", 0)
  end

  test "heatmap widgets reuse distribution datasets in 3d mode", %{series: series} do
    items = [
      %{
        "id" => "heat-1",
        "type" => "heatmap",
        "mode" => "2d",
        "paths" => ["metrics.distribution.*"],
        "path_aggregation" => "avg",
        "color_mode" => "single",
        "color_config" => %{"single_color" => "#14b8a6"},
        "designators" => %{
          "horizontal" => %{"type" => "custom", "buckets" => [10, 20]},
          "vertical" => %{"type" => "custom", "buckets" => [10, 20]}
        }
      }
    ]

    %{
      distribution: [
        %{
          id: "heat-1",
          mode: mode,
          chart_type: chart_type,
          points?: points?,
          path_aggregation: path_aggregation,
          color_mode: color_mode,
          color_config: color_config
        }
      ]
    } =
      WidgetData.datasets(series, items)

    assert mode == "3d"
    assert chart_type == "heatmap"
    assert path_aggregation == "mean"
    assert color_mode == "single"
    assert color_config["single_color"] == "#14B8A6"
    assert points?
  end

  test "kpi selector applies visual color", %{series: series} do
    items = [
      %{
        "id" => "kpi-color",
        "type" => "kpi",
        "path" => "metrics.count",
        "function" => "mean",
        "timeseries" => true,
        "series_color_selectors" => %{"metrics.count" => "warm.4"}
      }
    ]

    %{kpi_visuals: [%{id: "kpi-color", color: color}]} = WidgetData.datasets(series, items)

    assert color == Helpers.resolve_series_color("warm.4", 0)
  end

  test "list wildcard selector with fixed index applies one color across entries", %{
    series: series
  } do
    items = [
      %{
        "id" => "list-fixed",
        "type" => "list",
        "path" => "metrics.category.*",
        "series_color_selectors" => %{"metrics.category.*" => "default.3"}
      }
    ]

    %{list: [%{items: list_items}]} = WidgetData.datasets(series, items)

    assert length(list_items) >= 2

    assert Enum.uniq(Enum.map(list_items, & &1.color)) == [
             Helpers.resolve_series_color("default.3", 0)
           ]
  end

  test "list wildcard selector with palette rotation rotates colors per entry", %{series: series} do
    items = [
      %{
        "id" => "list-rotate",
        "type" => "list",
        "path" => "metrics.category.*",
        "series_color_selectors" => %{"metrics.category.*" => "default.*"}
      }
    ]

    %{list: [%{items: list_items}]} = WidgetData.datasets(series, items)
    assert length(list_items) >= 2

    first_color = list_items |> Enum.at(0) |> Map.get(:color)
    second_color = list_items |> Enum.at(1) |> Map.get(:color)

    assert first_color == Helpers.resolve_series_color("default.*", 0)
    assert second_color == Helpers.resolve_series_color("default.*", 1)
  end

  test "table selectors apply per configured path", %{series: series} do
    items = [
      %{
        "id" => "table-colors",
        "type" => "table",
        "paths" => ["metrics.table.payments.credit", "metrics.table.payments.digital"],
        "path_inputs" => ["metrics.table.payments.credit", "metrics.table.payments.digital"],
        "series_color_selectors" => %{
          "metrics.table.payments.credit" => "default.1",
          "metrics.table.payments.digital" => "default.6"
        }
      }
    ]

    %{table: [%{rows: rows}]} = WidgetData.datasets(series, items)

    credit_row = Enum.find(rows, &(&1.path == "metrics.table.payments.credit"))
    digital_row = Enum.find(rows, &(&1.path == "metrics.table.payments.digital"))

    assert credit_row.path_html =~ Helpers.resolve_series_color("default.1", 0)
    assert digital_row.path_html =~ Helpers.resolve_series_color("default.6", 0)
  end
end
