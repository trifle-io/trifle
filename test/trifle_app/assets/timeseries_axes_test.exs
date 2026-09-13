defmodule TrifleApp.Assets.TimeseriesAxesTest do
  use ExUnit.Case, async: true

  test "both timeseries renderers share axis routing, mixed series, units and weighted legend updates" do
    for path <- [
          "assets/js/widgets/dashboard_runtime/dashboard_grid_renderers/timeseries.js",
          "assets/js/widgets/dashboard_runtime/expanded_widget_view_hook.js"
        ] do
      source = File.read!(path)
      assert source =~ "timeseriesSeriesOptions(s,"
      assert source =~ "yAxis: timeseriesYAxes(yAxis,"
      assert source =~ "formatTimeseriesValue(raw,"
      assert source =~ "finalSeries.filter((s) => s.yAxisIndex !== 1)"
      assert source =~ "bindTimeseriesAverageLegend(chart,"
      assert source =~ "escapeTimeseriesTooltipHtml(value)"
    end
  end

  test "hover-only tooltips use the hovered series coordinate system, not a hardcoded primary axis" do
    source = File.read!("assets/js/widgets/dashboard_runtime/shared/timeseries_annotations.js")
    assert source =~ "? { seriesIndex: param.seriesIndex }"
    assert source =~ "chart.convertToPixel(finder, [x, y])"
  end
end
