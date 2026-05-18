defmodule TrifleApp.Components.DashboardWidgets.MetricSeriesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  @endpoint TrifleWeb.Endpoint

  alias TrifleApp.Components.DashboardWidgets.{
    MetricSeries,
    SeriesAliases,
    TableEditor,
    TimeseriesEditor
  }

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
    assert html =~ ~s(data-role="series-path")
    assert html =~ ~s(data-path-autocomplete-input="true")
    assert html =~ ~s(data-paths=)
    assert html =~ "state.success"
    refute html =~ "overflow-hidden rounded-md border border-gray-300"
    refute html =~ ~s(class="relative z-20")
    assert html =~ "top-full z-50"
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

    assert html =~ "rounded-xl border border-gray-200"
    assert html =~ "divide-y divide-gray-200"
    refute html =~ "overflow-hidden rounded-xl border border-gray-200"
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
    assert Regex.match?(~r/name="series_priority_last".*dark:bg-slate-800/s, html)
    assert Regex.match?(~r/name="series_aliases".*dark:bg-slate-800/s, html)
    assert Regex.match?(~r/name="ts_y_label".*dark:bg-slate-800/s, html)

    assert html =~
             "rounded-xl border border-gray-200 bg-white/40 dark:border-slate-700 dark:bg-slate-900/20"
  end

  test "timeseries editor renders visual series display rows by default while preserving raw fields" do
    html =
      render_component(&TimeseriesEditor.editor/1,
        widget: %{
          "id" => "timeseries-1",
          "type" => "timeseries",
          "series" => [],
          "series_aliases" => %{"seller1" => "me"},
          "series_priority" => ["me"],
          "series_priority_last" => ["other"]
        },
        path_options: []
      )

    assert html =~ ~s(phx-hook="SeriesDisplayEditor")
    assert html =~ "Advanced"
    refute Regex.match?(~r/<details[^>]+id="series-display-editor-timeseries-1"[^>]+open/, html)
    assert html =~ ~s(name="series_display_mode" value="visual")
    assert html =~ ~s(data-series-display-mode-panel="visual")
    assert html =~ ~s(name="series_alias_key[0]" value="seller1")
    assert html =~ ~s(name="series_alias_value[0]" value="me")
    assert html =~ ~s(name="series_priority_item[0]" value="me")
    assert html =~ ~s(name="series_priority_group[0]" value="first")
    assert html =~ "All other series"
    assert html =~ ~s(name="series_priority_item[2]" value="other")
    assert html =~ ~s(name="series_priority_group[2]" value="last")
    assert html =~ ~s(name="series_aliases")
    assert html =~ ~s(name="series_priority")
    assert html =~ ~s(name="series_priority_last")
  end

  test "timeseries editor opens raw mode when aliases JSON has an error" do
    html =
      render_component(&TimeseriesEditor.editor/1,
        widget: %{
          "id" => "timeseries-1",
          "type" => "timeseries",
          "series" => [],
          SeriesAliases.raw_text_key() => "{",
          SeriesAliases.error_key() => "Aliases must be valid JSON."
        },
        path_options: []
      )

    assert html =~ ~s(name="series_display_mode" value="raw")
    assert Regex.match?(~r/<details[^>]+id="series-display-editor-timeseries-1"[^>]+open/, html)
    assert html =~ "Aliases must be valid JSON."
    assert html =~ ~s(data-series-display-mode-panel="visual" hidden)
  end

  test "timeseries editor preserves draft raw mode without an aliases error" do
    html =
      render_component(&TimeseriesEditor.editor/1,
        widget: %{
          "id" => "timeseries-1",
          "type" => "timeseries",
          "series" => [],
          SeriesAliases.display_mode_key() => "raw"
        },
        path_options: []
      )

    assert html =~ ~s(name="series_display_mode" value="raw")
  end
end
