defmodule Trifle.Chat.InlineDashboardTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.InlineDashboard

  describe "normalize_grid/1" do
    test "auto-places widgets and applies widget defaults" do
      grid = [
        %{"type" => "kpi", "path" => "metrics.count", "title" => "Orders"},
        %{"type" => "timeseries", "paths" => ["metrics.count"], "title" => "Trend"},
        %{"type" => "text", "title" => "Notes"}
      ]

      assert {:ok, [kpi, timeseries, text]} = InlineDashboard.normalize_grid(grid)

      assert kpi["id"] == "widget-1"
      assert kpi["x"] == 0
      assert kpi["y"] == 0
      assert kpi["w"] == 3
      assert kpi["h"] == 2

      assert timeseries["id"] == "widget-2"
      assert timeseries["x"] == 0
      assert timeseries["y"] == 2
      assert timeseries["w"] == 12
      assert timeseries["h"] == 4

      assert text["id"] == "widget-3"
      assert text["subtype"] == "header"
      assert text["x"] == 0
      assert text["y"] == 6
    end

    test "rejects widgets missing required metric fields" do
      assert {:error, %{error: error}} = InlineDashboard.normalize_grid([%{"type" => "kpi"}])

      assert error =~ "requires at least one of: path"
    end

    test "clamps explicit positions and prevents overlaps by moving later widgets down" do
      grid = [
        %{
          "id" => "manual-1",
          "type" => "kpi",
          "path" => "metrics.count",
          "title" => "Orders",
          "x" => 10,
          "y" => 0,
          "w" => 4,
          "h" => 2
        },
        %{
          "id" => "manual-2",
          "type" => "kpi",
          "path" => "metrics.revenue",
          "title" => "Revenue",
          "x" => 10,
          "y" => 0,
          "w" => 4,
          "h" => 2
        }
      ]

      assert {:ok, [first, second]} = InlineDashboard.normalize_grid(grid)

      assert first["x"] == 8
      assert first["y"] == 0
      assert second["x"] == 8
      assert second["y"] == 2
    end

    test "rejects alias chart fields from model payloads" do
      grid = [
        %{"type" => "timeseries", "paths" => ["revenue"], "title" => "Revenue", "style" => "bar"},
        %{"type" => "category", "paths" => ["products.*"], "title" => "Products", "chart" => "pie"}
      ]

      assert {:error, %{error: error}} = InlineDashboard.normalize_grid(grid)
      assert error =~ "must use chart_type instead of style"
    end

    test "rejects pie-labelled category widgets without pie chart_type" do
      grid = [
        %{"type" => "category", "paths" => ["products.*"], "title" => "Products (pie)", "chart_type" => "bar"}
      ]

      assert {:error, %{error: error}} = InlineDashboard.normalize_grid(grid)
      assert error =~ "Category widget"
      assert error =~ "chart_type is not pie or donut"
    end

    test "rejects distribution widgets labelled as pie charts" do
      grid = [
        %{"type" => "distribution", "paths" => ["products.*"], "title" => "Products (pie)"}
      ]

      assert {:error, %{error: error}} = InlineDashboard.normalize_grid(grid)
      assert error =~ "cannot render pie or donut charts"
    end

  end

  describe "build_visualization/5" do
    test "builds a dashboard block and rehydrates render state from stored series snapshot" do
      grid = [
        %{"type" => "kpi", "path" => "metrics.count", "title" => "Orders"},
        %{"type" => "timeseries", "paths" => ["metrics.count"], "title" => "Trend"}
      ]

      snapshot = %{
        "at" => ["2024-01-01T00:00:00Z", "2024-01-02T00:00:00Z"],
        "values" => [
          %{"metrics" => %{"count" => 5}},
          %{"metrics" => %{"count" => 7}}
        ]
      }

      source = %{
        "id" => "db-1",
        "type" => "database",
        "display_name" => "Main DB",
        "time_zone" => "Etc/UTC"
      }

      assert {:ok, visualization} =
               InlineDashboard.build_visualization(
                 source,
                 "event::signup",
                 grid,
                 snapshot,
                 title: "Signup Overview",
                 timeframe: %{
                   from: "2024-01-01T00:00:00Z",
                   to: "2024-01-02T00:00:00Z",
                   label: "24h",
                   granularity: "1h"
                 },
                 default_timeframe: "24h",
                 default_granularity: "1h"
               )

      assert visualization["type"] == "dashboard"
      assert visualization["title"] == "Signup Overview"
      assert visualization["dashboard"]["payload"]["grid"] |> length() == 2
      assert visualization["series_snapshot"]["at"] == snapshot["at"]

      assert {:ok, render_state} = InlineDashboard.render_state(visualization)

      assert render_state.dashboard.id == visualization["dashboard"]["id"]
      assert map_size(render_state.dataset_maps.kpi_values) == 1
      assert map_size(render_state.dataset_maps.timeseries) == 1
    end

    test "rejects oversized stored series snapshots during render rehydration" do
      grid = [
        %{"type" => "timeseries", "paths" => ["metrics.count"], "title" => "Trend"}
      ]

      snapshot = %{
        "at" =>
          for idx <- 1..1001 do
            "2024-01-#{String.pad_leading(Integer.to_string(rem(idx, 28) + 1), 2, "0")}T00:00:00Z"
          end,
        "values" =>
          for idx <- 1..1001 do
            %{"metrics" => %{"count" => idx}}
          end
      }

      source = %{
        "id" => "db-1",
        "type" => "database",
        "display_name" => "Main DB",
        "time_zone" => "Etc/UTC"
      }

      assert {:ok, visualization} =
               InlineDashboard.build_visualization(
                 source,
                 "event::signup",
                 grid,
                 snapshot,
                 title: "Oversized Signup Overview",
                 timeframe: %{
                   from: "2024-01-01T00:00:00Z",
                   to: "2024-03-01T00:00:00Z",
                   label: "60d",
                   granularity: "1h"
                 },
                 default_timeframe: "60d",
                 default_granularity: "1h"
               )

      assert {:error, %{error: error}} = InlineDashboard.render_state(visualization)
      assert error =~ "chat limit of 1000 points"
    end
  end
end
