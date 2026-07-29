defmodule TrifleApp.Assets.TimeseriesTooltipResponsiveTest do
  use ExUnit.Case, async: true

  @shared_source_path "assets/js/widgets/dashboard_runtime/shared/timeseries_annotations.js"
  @dashboard_source_path "assets/js/widgets/dashboard_runtime/dashboard_grid_renderers/timeseries.js"
  @expanded_source_path "assets/js/widgets/dashboard_runtime/expanded_widget_view_hook.js"

  test "shared tooltip styles cap width and wrap long content" do
    source = File.read!(@shared_source_path)

    assert source =~ "export const TIMESERIES_TOOLTIP_RESPONSIVE_CSS"
    assert source =~ "max-width:min(30rem, calc(100vw - 2rem))"
    assert source =~ "white-space:normal"
    assert source =~ "overflow-wrap:anywhere"
    assert source =~ "word-break:break-word"
  end

  test "dashboard timeseries tooltips use responsive styles and stay within the chart" do
    source = File.read!(@dashboard_source_path)

    assert source =~ "TIMESERIES_TOOLTIP_RESPONSIVE_CSS"
    assert source =~ "confine: true"

    assert source =~
             "extraCssText: `z-index:${TIMESERIES_TOOLTIP_Z_INDEX};${TIMESERIES_TOOLTIP_RESPONSIVE_CSS}`"
  end

  test "expanded timeseries tooltips use responsive styles and stay within the chart" do
    source = File.read!(@expanded_source_path)

    assert source =~ "TIMESERIES_TOOLTIP_RESPONSIVE_CSS"
    assert source =~ "confine: true"
    assert source =~ "extraCssText: TIMESERIES_TOOLTIP_RESPONSIVE_CSS"
  end
end
