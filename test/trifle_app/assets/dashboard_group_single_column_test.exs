defmodule TrifleApp.Assets.DashboardGroupSingleColumnTest do
  use ExUnit.Case, async: true

  @source_path "assets/js/widgets/dashboard_runtime/dashboard_grid_hook.js"

  test "single-column group geometry uses stacked child rows instead of fixed group height" do
    source = File.read!(@source_path)

    assert source =~ "_groupStackedRowCount(groupItem, grid = null)"
    assert source =~ "const storedMultiColumnH ="
    assert source =~ "storedMultiColumnH ||"
    assert source =~ "if (this._isOneCol) {"

    assert source =~
             "return Math.max(this._groupBaseRowCount(groupItem), this._groupStackedRowCount(groupItem, grid));"

    assert source =~
             "const cellHeight = this._isOneCol ? this._nestedCellHeight : Math.max(24, availableHeight / rows);"
  end

  test "single-column group geometry expands the outer group item and restores multi-column height" do
    source = File.read!(@source_path)

    assert source =~ "_syncResponsiveGroupItemHeight(groupItem, metrics)"
    assert source =~ "groupItem.dataset.multiColumnH"
    assert source =~ "const targetH = metrics.rows + this._groupChromeRows(groupItem);"
    assert source =~ "this._syncResponsiveGroupItemHeight(groupItem, metrics);"
  end

  test "responsive group height changes go through the GridStack element so siblings are relaid out" do
    source = File.read!(@source_path)

    assert source =~ "_updateRootGridItemHeight(rootGrid, groupItem, targetH)"
    assert source =~ "rootGrid.update(groupItem, { h: targetH })"
    assert source =~ "this._updateRootGridItemHeight(rootGrid, groupItem, storedH)"
    refute source =~ "rootGrid.update(node, { h: targetH })"
  end

  test "single-column group geometry restacks all nested widgets vertically" do
    source = File.read!(@source_path)

    assert source =~ "_syncNestedResponsiveLayout(nestedGrid)"
    assert source =~ "this._orderedGridItems(nestedGrid)"
    assert source =~ "const target = { x: 0, y, w: 1, h }"
    assert source =~ "y += h"
    assert source =~ "this._updateGridItemGeometry(nestedGrid, item, target)"
  end

  test "restores nested widgets after returning to multi-column before applying saved x and width" do
    source = File.read!(@source_path)

    assert source =~ "const desiredCols = this._groupColumnCount(groupItem);"
    assert source =~ "nestedGrid.column(desiredCols, 'none')"

    [_before, sync_group_geometry] =
      String.split(source, "_syncGroupGridGeometry(groupItem, grid = null)", parts: 2)

    column_position =
      :binary.match(sync_group_geometry, "nestedGrid.column(desiredCols, 'none')") |> elem(0)

    restore_position =
      :binary.match(sync_group_geometry, "this._syncNestedResponsiveLayout(nestedGrid)")
      |> elem(0)

    assert column_position < restore_position
  end

  test "responsive transitions clear stale timeseries hover overlays before charts are resized" do
    source = File.read!(@source_path)

    assert source =~ "_clearTimeseriesHoverState()"
    assert source =~ "chart.dispatchAction({ type: 'hideTip' })"
    assert source =~ "chart.dispatchAction({ type: 'downplay', seriesIndex: 0 })"
    assert source =~ "this._clearTimeseriesHoverState();"
  end
end
