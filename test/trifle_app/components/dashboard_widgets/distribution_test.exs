defmodule TrifleApp.Components.DashboardWidgets.DistributionTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.Distribution

  setup do
    timestamps =
      [
        DateTime.from_naive!(~N[2024-01-01 00:00:00], "Etc/UTC"),
        DateTime.from_naive!(~N[2024-01-01 01:00:00], "Etc/UTC")
      ]

    values = [
      %{
        "metrics" => %{
          "distribution" => %{"10" => 1, "20" => 2},
          "other" => %{"bucket" => 5}
        }
      },
      %{
        "metrics" => %{
          "distribution" => %{"10" => 2, "30" => 1},
          "other" => %{"bucket" => 8}
        }
      }
    ]

    series = %Trifle.Stats.Series{series: %{at: timestamps, values: values}}

    %{series: series}
  end

  test "builds buckets using custom designator", %{series: series} do
    widget = %{
      "id" => "dist-1",
      "type" => "distribution",
      "paths" => ["metrics.distribution.*"],
      "designator" => %{"type" => "custom", "buckets" => [10, 20]}
    }

    dataset = Distribution.dataset(series, widget)

    assert dataset.bucket_labels == ["10", "20", "20+"]
    assert dataset.vertical_bucket_labels == ["10", "20", "20+"]
    assert dataset.errors == []

    assert %{
             bucket_labels: ["10", "20", "20+"],
             config: %{buckets: [10.0, 20.0]},
             type: :custom
           } = dataset.designators["horizontal"]

    assert [%{values: values}] = dataset.series

    assert Enum.find(values, &(&1.bucket == "10")).value > 0
    assert Enum.find(values, &(&1.bucket == "20")).value >= 0
    assert Enum.find(values, &(&1.bucket == "20+")).value >= 0
  end

  test "populates linear buckets even when missing data", %{series: series} do
    widget = %{
      "id" => "dist-linear",
      "type" => "distribution",
      "paths" => ["metrics.latency.*"],
      "designator" => %{"type" => "linear", "min" => 0, "max" => 30, "step" => 10}
    }

    dataset = Distribution.dataset(series, widget)

    assert dataset.bucket_labels == ["0", "10", "20", "30", "30+"]
    assert dataset.vertical_bucket_labels == ["0", "10", "20", "30", "30+"]
    assert dataset.errors == []
    assert [%{values: values}] = dataset.series

    assert Enum.all?(values, &(&1.value == 0.0))
  end

  test "uses default designator when configuration is missing", %{series: series} do
    widget = %{
      "id" => "dist-error",
      "type" => "distribution",
      "paths" => ["metrics.distribution.*"]
    }

    dataset = Distribution.dataset(series, widget)

    assert dataset.bucket_labels == ["10", "20", "30", "30+"]
    assert dataset.errors == []
    assert dataset.designator.config == %{buckets: [10.0, 20.0, 30.0]}
  end

  test "respects separate vertical designator in 3d mode", %{series: series} do
    widget = %{
      "id" => "dist-3d",
      "type" => "distribution",
      "mode" => "3d",
      "paths" => ["metrics.distribution.*"],
      "designators" => %{
        "horizontal" => %{"type" => "custom", "buckets" => [10, 20]},
        "vertical" => %{"type" => "linear", "min" => 0, "max" => 30, "step" => 15}
      }
    }

    dataset = Distribution.dataset(series, widget)

    assert dataset.bucket_labels == ["10", "20", "20+"]
    assert dataset.vertical_bucket_labels == ["0", "15", "30", "30+"]
    assert dataset.errors == []
    assert dataset.designators["vertical"].config == %{max: 30.0, min: 0.0, step: 15.0}
  end

  test "ignores invalid vertical designator when in 2d mode", %{series: series} do
    widget = %{
      "id" => "dist-2d-bad-vertical",
      "type" => "distribution",
      "paths" => ["metrics.distribution.*"],
      "mode" => "2d",
      "designators" => %{
        "horizontal" => %{"type" => "linear", "min" => 0, "max" => 20, "step" => 10},
        "vertical" => %{"type" => "linear", "min" => 5, "max" => 0, "step" => 5}
      }
    }

    dataset = Distribution.dataset(series, widget)

    assert dataset.bucket_labels == ["0", "10", "20", "20+"]
    assert dataset.vertical_bucket_labels == nil
    assert dataset.errors == []
    refute Map.has_key?(dataset.designators, "vertical")
  end

  test "builds 3d points with horizontal and vertical designators" do
    series =
      %Trifle.Stats.Series{
        series: %{
          values: [
            %{"latency" => %{"100" => %{"200" => 1}, "200" => %{"200" => 2}}}
          ]
        }
      }

    widget = %{
      "id" => "dist-3d",
      "type" => "distribution",
      "mode" => "3d",
      "paths" => ["latency"],
      "designators" => %{
        "horizontal" => %{"type" => "custom", "buckets" => [100, 200]},
        "vertical" => %{"type" => "custom", "buckets" => [200]}
      }
    }

    dataset = Distribution.dataset(series, widget)

    assert dataset.bucket_labels == ["100", "200", "200+"]
    assert dataset.vertical_bucket_labels == ["200", "200+"]
    assert [%{points: points}] = dataset.series

    assert %{
             bucket_x: "100",
             bucket_y: "200",
             value: 1.0
           } in points

    assert %{
             bucket_x: "200",
             bucket_y: "200",
             value: 2.0
           } in points

    assert dataset.errors == []
  end
end
