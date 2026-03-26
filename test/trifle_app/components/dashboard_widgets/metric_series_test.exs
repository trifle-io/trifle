defmodule TrifleApp.Components.DashboardWidgets.MetricSeriesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint TrifleWeb.Endpoint

  alias TrifleApp.Components.DashboardWidgets.{MetricSeries, TableEditor, TimeseriesEditor}

  test "normalize_widget drops synthetic blank rows for persisted widgets" do
    widget = %{
      "type" => "timeseries",
      "series" => [
        %{
          "kind" => "path",
          "path" => "",
          "expression" => "",
          "label" => "",
          "visible" => true,
          "color_selector" => "default.*"
        }
      ]
    }

    normalized = MetricSeries.normalize_widget(widget)

    assert normalized["series"] == []
  end

  test "normalize_widget_for_form keeps a default draft row for empty widgets" do
    widget = %{"type" => "timeseries", "series" => []}

    normalized = MetricSeries.normalize_widget_for_form(widget)

    assert [
             %{
               "kind" => "path",
               "path" => "",
               "expression" => "",
               "label" => "",
               "visible" => true
             }
           ] = normalized["series"]
  end

  test "normalize_widget preserves legacy single path widgets for multi-row types" do
    widget = %{
      "type" => "table",
      "path" => "metrics.count",
      "series_color_selectors" => %{"metrics.count" => "default.3"}
    }

    normalized = MetricSeries.normalize_widget(widget)

    assert [
             %{
               "kind" => "path",
               "path" => "metrics.count",
               "color_selector" => "default.3"
             }
           ] = normalized["series"]

    refute Map.has_key?(normalized, "path")
    refute Map.has_key?(normalized, "series_color_selectors")
  end

  test "normalize_widget recognizes widget_type-only maps during migration" do
    widget = %{
      "widget_type" => "table",
      "path" => "metrics.count"
    }

    normalized = MetricSeries.normalize_widget(widget)

    assert [%{"path" => "metrics.count"}] = normalized["series"]
  end

  test "normalize_widget drops blank hidden rows as empty" do
    widget = %{
      "type" => "timeseries",
      "series" => [
        %{
          "kind" => "path",
          "path" => "",
          "expression" => "",
          "label" => "",
          "visible" => false,
          "color_selector" => "default.*"
        }
      ]
    }

    normalized = MetricSeries.normalize_widget(widget)

    assert normalized["series"] == []
  end

  test "table editor renders its custom path help" do
    html =
      render_component(&TableEditor.editor/1,
        widget: %{"id" => "table-1", "type" => "table", "series" => []},
        path_options: []
      )

    assert html =~ "Path rows become table rows; timestamps are the columns."
    refute html =~ "Hidden source rows can feed visible expression rows."
  end

  test "table editor exposes accessible names for series kind controls" do
    html =
      render_component(&TableEditor.editor/1,
        widget: %{"id" => "table-1", "type" => "table", "series" => []},
        path_options: []
      )

    assert html =~ ~s(aria-label="Path series")
    assert html =~ ~s(aria-label="Expression series")
  end

  test "table editor scopes ids for atom-keyed widgets" do
    html =
      render_component(&TableEditor.editor/1,
        widget: %{id: "table-atom", type: "table", series: []},
        path_options: []
      )

    assert html =~ ~s(id="widget-table-atom-series")
    assert html =~ ~s(data-widget-id="table-atom")
    assert html =~ ~s(id="widget-series-row-table-atom-0")
    assert html =~ ~s(id="widget-series-path-table-atom-0")
    assert html =~ "widget-series-color-table-atom"
  end

  test "table editor renders annotated widget path inputs" do
    html =
      render_component(&TableEditor.editor/1,
        widget: %{"id" => "table-annotated", "type" => "table", "series" => []},
        path_options: [%{"value" => "state.success", "label" => "state.success"}]
      )

    assert html =~ ~s(data-role="path-preview")
    assert html =~ ~s(data-paths=)
    assert html =~ "state.success"
    refute html =~ "overflow-hidden rounded-md border border-gray-300"
  end

  test "table editor keeps series rows in a two-line mobile layout before desktop grid" do
    html =
      render_component(&TableEditor.editor/1,
        widget: %{"id" => "table-layout", "type" => "table", "series" => []},
        path_options: []
      )

    assert html =~ "lg:grid-cols-[auto_minmax(0,1.6fr)_14rem_12rem_auto]"
    assert html =~ "grid-cols-[minmax(0,1fr)_9rem_auto]"
    assert html =~ "sm:grid-cols-[minmax(0,1fr)_12rem_auto]"
  end

  test "table editor renders series rows as a divided list instead of stacked cards" do
    html =
      render_component(&TableEditor.editor/1,
        widget: %{"id" => "table-list", "type" => "table", "series" => []},
        path_options: []
      )

    assert html =~ "overflow-hidden rounded-xl border border-gray-200"
    assert html =~ "divide-y divide-gray-200"
    refute html =~ "rounded-lg border border-gray-200 bg-white px-3 py-3"
  end

  test "timeseries editor keeps visible input surfaces on a consistent dark token" do
    html =
      render_component(&TimeseriesEditor.editor/1,
        widget: %{"id" => "timeseries-1", "type" => "timeseries", "series" => []},
        path_options: []
      )

    assert Regex.match?(~r/name="widget_series_label\[0\]".*dark:bg-slate-800/s, html)
    assert Regex.match?(~r/name="series_priority".*dark:bg-slate-800/s, html)
    assert Regex.match?(~r/name="ts_y_label".*dark:bg-slate-800/s, html)

    assert html =~
             "rounded-xl border border-gray-200 bg-white/40 px-4 py-4 dark:border-slate-700 dark:bg-slate-900/20"
  end
end
