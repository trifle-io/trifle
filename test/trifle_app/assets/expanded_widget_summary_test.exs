defmodule TrifleApp.Assets.ExpandedWidgetSummaryTest do
  use ExUnit.Case, async: true

  @source_path "assets/js/widgets/dashboard_runtime/expanded_widget_view_hook.js"
  @styles_path "assets/css/app.css"
  @aggrid_utils_path "assets/js/utils/aggrid.js"
  @dashboard_table_path "assets/js/widgets/dashboard_runtime/dashboard_grid_renderers/table.js"
  @expanded_table_path "assets/js/widgets/dashboard_runtime/expanded_aggrid_table_hook.js"

  test "series summary follows KPI aggregate names and order" do
    source = File.read!(@source_path)
    [_before, columns] = String.split(source, "  summaryColumnDefs() {", parts: 2)

    positions =
      ["'Path'", "'Mean'", "'Sum'", "'Max'", "'Min'", "'Oldest'", "'Latest'"]
      |> Enum.map(fn label ->
        {position, _length} = :binary.match(columns, label)
        position
      end)

    assert positions == Enum.sort(positions)
    assert source =~ "const oldest = values[0];"
    assert source =~ "const latest = values[values.length - 1];"
    assert source =~ "return { mean, sum, max, min, oldest, latest };"
  end

  test "series summary uses sortable AG Grid columns with numeric missing-value handling" do
    source = File.read!(@source_path)

    assert source =~ "ensureAgGridCommunity()"
    assert source =~ "sortingOrder: ['asc', 'desc', null]"
    assert source =~ "sortable: true"
    assert source =~ "comparator: this.summaryNumericComparator.bind(this)"
    assert source =~ "if (!hasA) return isDescending ? -1 : 1;"
    assert source =~ "if (!hasB) return isDescending ? 1 : -1;"
    assert source =~ "return Number.isFinite(value) ? this.formatSummaryRaw(value) : '—';"
    refute source =~ "return Number.isFinite(value) ? formatCompactNumber(value) : '—';"
  end

  test "category expanded data uses the shared sortable grid with full numeric values" do
    source = File.read!(@source_path)

    assert source =~ "this.summaryPathColumn('Category')"
    assert source =~ "this.summaryNumericColumn('value', 'Value')"
    assert source =~ "this.renderSummaryGrid(rows, this.categoryColumnDefs());"

    [_before, category_table] = String.split(source, "  renderCategoryTable(data) {", parts: 2)

    [category_table, _after] =
      String.split(category_table, "  activateFastTooltips() {", parts: 2)

    refute category_table =~ "<table"
    refute category_table =~ "formatCompactNumber"
  end

  test "summary grid preserves sorting while live data updates and cleans up its lifecycle" do
    source = File.read!(@source_path)

    assert source =~ ".getColumnState()"
    assert source =~ ".applyColumnState({ state: sortState })"
    assert source =~ "this.destroySummaryGrid();"
    assert source =~ "this.summaryResizeObserver.disconnect()"
    assert source =~ "this.summaryGrid.api.destroy()"
  end

  test "summary and category grids allow selecting and copying cell text" do
    source = File.read!(@source_path)

    assert source =~ "enableRangeSelection: true"
    assert source =~ "enableCellTextSelection: true"
  end

  test "summary and category path columns auto-size to content within configured bounds" do
    source = File.read!(@source_path)

    assert source =~ "this.autoSizeSummaryPathColumn(rows);"
    assert source =~ "this.summaryGrid.columnApi.autoSizeColumns(['path'], false)"
    assert source =~ "const measuredWidth = this.measureSummaryPathWidth(rows);"
    assert source =~ "const clamped = Math.max(minWidth, Math.min(maxWidth, desiredWidth));"
    assert source =~ "this.summaryGrid.columnApi.setColumnWidth(column, clamped)"
    assert source =~ "return Math.ceil(widestLabel + 56);"
    assert source =~ "resizable: true"
  end

  test "sorting remains scoped to the expanded series summary" do
    dashboard_table = File.read!(@dashboard_table_path)
    expanded_table = File.read!(@expanded_table_path)

    assert dashboard_table =~ "sortable: false"
    assert expanded_table =~ "sortable: false"
  end

  test "summary grid headings remain sentence case and do not wrap" do
    source = File.read!(@source_path)
    styles = File.read!(@styles_path)

    assert source =~ "headerComponent: getAggridHeaderComponentClass()"
    assert source =~ "headerComponentParams: { lines: [headerName], align: 'left' }"
    assert source =~ "headerComponentParams: { lines: [headerName], align: 'right' }"
    assert source =~ "headerClass: 'aggrid-header-cell ag-left-aligned-header'"
    assert source =~ "headerClass: 'aggrid-header-cell ag-right-aligned-header'"
    assert styles =~ ".aggrid-summary-table-shell .ag-header-cell-text"
    assert styles =~ ".aggrid-summary-table-shell .ag-header-cell-comp-wrapper"

    assert styles =~
             ".aggrid-summary-table-shell .aggrid-header-cell-wrapper.aggrid-header-align-right"

    assert styles =~ ".aggrid-summary-table-shell .ag-right-aligned-header .ag-header-cell-text"
    assert styles =~ "justify-content: flex-end;"
    assert styles =~ "text-align: right;"
    assert styles =~ "text-transform: none;"
    assert styles =~ "white-space: nowrap;"
  end

  test "custom aligned headers preserve mouse and keyboard sorting" do
    source = File.read!(@aggrid_utils_path)

    assert source =~ "params.progressSort(!!event.shiftKey)"
    assert source =~ "params.column.addEventListener('sortChanged', this.onSortChanged)"
    assert source =~ "params.column.removeEventListener('sortChanged', this.onSortChanged)"

    assert source =~
             "this.sortIndicator.textContent = sort === 'asc' ? '↑' : sort === 'desc' ? '↓' : '';"

    assert source =~ "this.params.eGridHeader.setAttribute('aria-sort', ariaSort)"
  end
end
