defmodule TrifleApp.Assets.ExpandedWidgetLegendTest do
  use ExUnit.Case, async: true

  @source_path "assets/js/widgets/dashboard_runtime/expanded_widget_view_hook.js"

  test "expanded chart legends ignore the widget legend configuration" do
    source = File.read!(@source_path)

    assert source =~ "const bottomPadding = 56;"
    assert source =~ "legend: { show: true, type: 'scroll', bottom: 6"
    assert source =~ "legend: { show: true }"
    assert source =~ "const showScale = true;"

    refute source =~ "const showLegend = !!data.legend;"
    refute source =~ "const legendFlag = data?.legend;"
    refute source =~ "resolveCategoryLegendVisible"
  end
end
