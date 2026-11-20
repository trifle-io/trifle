defmodule TrifleApp.Assets.TraceEntriesLayoutTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  @endpoint TrifleWeb.Endpoint

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

  test "compact differences stay inline while full timestamps reflow with detail width" do
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

    assert source =~
             ".trace-entries[data-show-timestamps=\"true\"]:not([data-timestamp-mode=\"raw\"]) .trace-entry {\n  grid-template-columns: var(--trace-line-width, 2ch) minmax(0, 1fr) max-content;"

    assert source =~
             ".trace-entries:not([data-timestamp-mode=\"raw\"]) .trace-entry-timestamp {\n  grid-column: 3;\n  grid-row: 1;\n  white-space: nowrap;"
  end

  test "overview uses the page section gap without adding a widget bottom margin" do
    source = File.read!(@source_path)

    assert source =~ "--traces-section-gap: 0.75rem;"

    assert source =~
             ".traces-workspace > [data-filter-bar-shortcuts] {\n  margin-bottom: var(--traces-section-gap);"

    assert source =~ "gap: var(--traces-section-gap);"

    overview = Trifle.Traces.Overview.build(nil, nil, nil, %{})

    doc =
      render_component(&TrifleApp.Components.TraceOverview.content/1,
        overview: overview,
        params: %{},
        path_colors: %{},
        timezone: "UTC"
      )
      |> Floki.parse_document!()

    [classes] = Floki.attribute(doc, "#trace-overview", "class")
    refute Enum.any?(String.split(classes), &Regex.match?(~r/^(?:.*:)?m[by]?-/, &1))
    assert Floki.find(doc, "#traces-dashboard-grid") == []
  end

  test "native sticky controls leave room for entries without JavaScript offsets" do
    source = File.read!(@source_path)
    assert source =~ ".trace-detail-header {"
    assert source =~ ".trace-detail-header {\n  top: 0;"
    assert source =~ "max-height: max(6rem, 35cqh);"
    assert source =~ ".trace-footer-panel {\n  max-height: min(24rem, 40cqh);\n  overflow: auto;"
    assert source =~ ".trace-list-split {\n  position: sticky;\n  top: 0;"
    assert source =~ "max-height: 100cqh;"
    refute source =~ "--trace-header-top"
    refute source =~ "--trace-detail-visible-height"

    app_js = File.read!(Path.expand("../../../assets/js/app.js", __DIR__))
    refute app_js =~ "TraceDetailSticky"
  end
end
