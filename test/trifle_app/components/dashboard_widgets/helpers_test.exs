defmodule TrifleApp.Components.DashboardWidgets.HelpersTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.DesignSystem.ChartColors

  test "normalizes and parses palette rotation selector" do
    assert Helpers.normalize_series_color_selector(" DEFAULT.* ") == "default.*"

    assert Helpers.parse_series_color_selector("default.*") == %{
             type: :palette_rotate,
             palette_id: "default"
           }
  end

  test "normalizes and parses palette fixed selector" do
    assert Helpers.normalize_series_color_selector("default.4") == "default.4"

    assert Helpers.parse_series_color_selector("default.4") == %{
             type: :single_palette,
             palette_id: "default",
             index: 4
           }
  end

  test "normalizes and parses custom selector" do
    assert Helpers.normalize_series_color_selector("custom.#14b8a6") == "custom.#14B8A6"

    assert Helpers.parse_series_color_selector("custom.#14b8a6") == %{
             type: :single_custom,
             color: "#14B8A6"
           }
  end

  test "falls back to default selector for invalid values" do
    assert Helpers.normalize_series_color_selector("foo") == "default.*"

    assert Helpers.parse_series_color_selector("foo") == %{
             type: :palette_rotate,
             palette_id: "default"
           }
  end

  test "resolves selector colors" do
    assert Helpers.resolve_series_color("default.2", 0) == ChartColors.color_at("default", 2)
    assert Helpers.resolve_series_color("default.*", 3) == ChartColors.color_for("default", 3)
    assert Helpers.resolve_series_color("custom.#FF00AA", 0) == "#FF00AA"
  end

  test "builds selector map from typed paths and selector list" do
    path_inputs = ["metrics.a.*", "metrics.b", ""]
    selector_values = ["default.*", "default.3", "default.1"]

    selectors =
      Helpers.normalize_series_color_selectors_for_paths(path_inputs, selector_values, %{})

    assert selectors == %{
             "metrics.a.*" => "default.*",
             "metrics.b" => "default.3"
           }
  end

  test "builds selector map from indexed selector params map" do
    path_inputs = ["metrics.a.*", "metrics.b", ""]
    selector_values = %{"0" => "default.*", "1" => "default.3", "2" => "default.1"}

    selectors =
      Helpers.normalize_series_color_selectors_for_paths(path_inputs, selector_values, %{})

    assert selectors == %{
             "metrics.a.*" => "default.*",
             "metrics.b" => "default.3"
           }
  end
end
