defmodule TrifleApp.Components.LayoutPreloadsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  test "preloads collapsed dashboard groups before the page renders" do
    html = render_component(&TrifleWeb.LayoutPreloads.preload_scripts/1, %{})

    assert html =~ "dashboard_group_collapsed_default"
    assert html =~ "trifle-dashboard-groups-preload"
    assert html =~ "data-dashboard-group-content"
    assert html =~ "data-dashboard-group-collapsed-icon"
    assert html =~ "data-dashboard-group-expanded-icon"
  end
end
