defmodule TrifleApp.Assets.FastTooltipTest do
  use ExUnit.Case, async: true

  @hooks_path Path.expand("../../../assets/js/hooks/status_hooks.js", __DIR__)
  @modal_path Path.expand("../../../lib/trifle_app/design_system/modal.ex", __DIR__)

  test "fast tooltips use one delegated document listener" do
    source = File.read!(@hooks_path)

    assert source =~ "document.addEventListener('mouseover'"
    assert source =~ "target.closest('[data-tooltip]')"
    assert source =~ "window.__fastTooltipDelegated"
    assert source =~ "matchesTooltipMedia"
    assert source =~ "tooltip.setAttribute('role', 'tooltip')"

    refute source =~ "fastTooltipBound"
    refute source =~ "this.el.querySelectorAll('[data-tooltip]"
  end

  test "fast tooltips render above the application modal layer" do
    hooks_source = File.read!(@hooks_path)
    modal_source = File.read!(@modal_path)

    [_, tooltip_z_index] = Regex.run(~r/z-index: (\d+);/, hooks_source)
    [_, modal_z_index] = Regex.run(~r/z-\[(\d+)\]/, modal_source)

    assert String.to_integer(tooltip_z_index) > String.to_integer(modal_z_index)
  end
end
