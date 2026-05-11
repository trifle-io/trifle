defmodule TrifleApp.Assets.DashboardGroupHeaderColorTest do
  use ExUnit.Case, async: true

  @source_path "assets/css/app.css"

  test "theme group title colors do not override computed custom header contrast" do
    source = File.read!(@source_path)

    assert source =~
             ".grid-stack-item-content[data-widget-type=\"group\"] .grid-widget-title:not(.text-current)"

    assert source =~
             ".dark .grid-stack-item-content[data-widget-type=\"group\"] .grid-widget-title:not(.text-current)"

    refute source =~
             ".grid-stack-item-content[data-widget-type=\"group\"] .grid-widget-title {\n  color:"

    refute source =~
             ".dark .grid-stack-item-content[data-widget-type=\"group\"] .grid-widget-title {\n  color:"
  end
end
