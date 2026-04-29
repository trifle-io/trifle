defmodule TrifleApp.Components.DashboardWidgets.KpiEditorTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TrifleApp.Components.DashboardWidgets.KpiEditor

  test "function selector includes oldest and latest options" do
    html =
      render_component(&KpiEditor.editor/1, %{
        widget: %{"id" => "kpi-1", "type" => "kpi", "function" => "latest", "unit" => "minutes"},
        path_options: []
      })

    assert html =~ "Oldest"
    assert html =~ "Latest"
    assert html =~ ~s(phx-value-function="oldest")
    assert html =~ ~s(phx-value-function="latest")
    assert html =~ ~s(name="kpi_function" value="latest")
    assert html =~ ~s(name="kpi_unit" value="minutes")
    assert html =~ "Unit"
  end
end
