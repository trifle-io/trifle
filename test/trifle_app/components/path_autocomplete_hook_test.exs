defmodule TrifleApp.Components.PathAutocompleteHookTest do
  use ExUnit.Case, async: true

  @hook_path "assets/js/hooks/path_autocomplete_hook.js"

  test "suggestion labels render trusted annotated path HTML instead of raw markup" do
    source = File.read!(@hook_path)

    refute source =~ "option.textContent = item.label"
    assert source =~ "option.innerHTML = item.label"
  end
end
