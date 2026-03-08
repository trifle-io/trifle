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
  end
end
