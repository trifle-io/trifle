defmodule TrifleApp.Assets.TraceEntriesLayoutTest do
  use ExUnit.Case, async: true

  @source_path Path.expand("../../../assets/css/app.css", __DIR__)

  test "one native scrollport fills the space below the naturally sized FilterBar" do
    source = File.read!(@source_path)

    assert source =~ ".traces-workspace {"
    assert source =~ "height: calc(100dvh - 7rem);"
    assert source =~ "height: calc(100dvh - 3rem);"
    assert source =~ "grid-template-rows: auto minmax(0, 1fr);"
    assert source =~ "container: traces-scrollport / size;"
    assert source =~ "min-height: 32rem;"
    assert source =~ "overflow: clip;"
    refute source =~ "min-height: min-content;"
  end

  test "entry columns reflow with detail width and timestamps reserve space only when shown" do
    source = File.read!(@source_path)

    assert source =~ "container: trace-entries / inline-size;"
    assert source =~ "grid-template-columns: var(--trace-line-width, 2ch) minmax(0, 1fr);"
    assert source =~ "@container trace-entries (min-width: 38rem)"
    assert source =~ ".trace-entries[data-show-timestamps=\"true\"] .trace-entry"

    assert source =~
             "grid-template-columns: var(--trace-line-width, 2ch) minmax(0, 1fr) max-content;"

    assert source =~ "padding-left: min(var(--trace-entry-indent, 0rem), 20%);"

    assert source =~
             ".trace-entry-timestamp {\n  grid-column: 2;\n  grid-row: 2;\n  justify-self: end;"

    assert source =~ ".trace-entry-timestamp {\n    grid-column: 3;\n    grid-row: 1;"
  end

  test "activity has equal compact gaps without stacking the widget bottom margin" do
    source = File.read!(@source_path)

    assert source =~ "--traces-section-gap: 0.75rem;"

    assert source =~
             ".traces-workspace > [data-filter-bar-shortcuts] {\n  margin-bottom: var(--traces-section-gap);"

    assert source =~ "gap: var(--traces-section-gap);"

    assert source =~
             ".traces-content > [aria-label=\"Trace activity\"] > .mb-6 {\n  margin-bottom: 0;"
  end

  test "native sticky header and list size themselves without JavaScript offsets" do
    source = File.read!(@source_path)
    assert source =~ ".trace-detail-header {"
    assert source =~ ".trace-detail-header {\n  top: 0;"
    assert source =~ "max-height: max(8rem, calc(100cqh - 5rem));"
    assert source =~ ".trace-list-split {\n  position: sticky;\n  top: 0;"
    assert source =~ "max-height: 100cqh;"
    refute source =~ "--trace-header-top"
    refute source =~ "--trace-detail-visible-height"

    app_js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
    refute app_js =~ "TraceDetailSticky"
  end
end
