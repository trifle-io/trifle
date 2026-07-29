defmodule TrifleApp.Assets.DashboardTextWidgetOverflowTest do
  use ExUnit.Case, async: true

  @source_path Path.expand(
                 "../../../assets/js/widgets/dashboard_runtime/dashboard_grid_renderers/text.js",
                 __DIR__
               )

  test "header text stays centered until it needs a reachable scroll origin" do
    source = File.read!(@source_path)

    assert source =~ "text-widget-body flex-col min-h-0"
    assert source =~ "body.style.justifyContent = 'safe center'"
    assert source =~ "body.style.overflowY = 'auto'"
  end
end
