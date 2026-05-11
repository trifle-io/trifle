defmodule TrifleApp.Components.PathAutocompleteHookTest do
  use ExUnit.Case, async: true

  @hook_path "assets/js/hooks/path_autocomplete_hook.js"

  test "suggestion labels render trusted annotated path HTML instead of raw markup" do
    source = File.read!(@hook_path)

    refute source =~ "option.textContent = item.label"
    assert source =~ "option.innerHTML = suggestionLabelHtml(item)"
    assert source =~ "decodeHtmlEntities(label)"
    assert source =~ "if (label === value) return escapePathPreviewHtml(value);"
  end

  test "annotated preview synchronizes text metrics with the real input caret" do
    source = File.read!(@hook_path)

    assert source =~ "syncPathPreviewMetrics()"
    assert source =~ "window.getComputedStyle(this.input)"
    assert source =~ "PATH_PREVIEW_FONT_PROPERTIES"
    assert source =~ "PATH_PREVIEW_LAYOUT_PROPERTIES"
    refute source =~ "this.input.style[property] = value"
    assert source =~ "this.pathPreview.style[property] = value"
    assert source =~ "this.pathPreview.style.borderColor = 'transparent'"
    assert source =~ "this.pathPreview.style.whiteSpace = 'pre'"
  end
end
