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

  test "normalizes widget surface selectors to single colors" do
    assert Helpers.normalize_surface_color_selector(nil) == nil
    assert Helpers.normalize_surface_color_selector("  ") == nil
    assert Helpers.normalize_surface_color_selector("default.*") == "default.0"
    assert Helpers.normalize_surface_color_selector("warm.4") == "warm.4"
    assert Helpers.normalize_surface_color_selector("custom.#14b8a6") == "custom.#14B8A6"
  end

  test "resolves widget surface styles with readable foreground colors" do
    default_surface = Helpers.resolve_surface_style(nil, default_background: "#FFFFFF")
    custom_surface = Helpers.resolve_surface_style("cool.4", default_background: "#FFFFFF")
    red_surface = Helpers.resolve_surface_style("default.2", default_background: "#FFFFFF")
    dark_surface = Helpers.resolve_surface_style("purple.6", default_background: "#FFFFFF")

    assert default_surface.default?
    assert default_surface.background == "#FFFFFF"
    assert default_surface.text == "#0F172A"
    refute custom_surface.default?
    assert custom_surface.background == "#0EA5E9"
    assert custom_surface.text == "#0F172A"
    assert red_surface.background == "#EF4444"
    assert red_surface.text == "#0F172A"
    assert dark_surface.background == "#4C1D95"
    assert dark_surface.text == "#F8FAFC"
  end

  test "resolves rotating surface styles by cycling through the selected palette" do
    first_surface =
      Helpers.resolve_surface_style("warm.*",
        default_background: "#FFFFFF",
        allow_palette_rotate: true,
        palette_index: 0
      )

    eighth_surface =
      Helpers.resolve_surface_style("warm.*",
        default_background: "#FFFFFF",
        allow_palette_rotate: true,
        palette_index: 7
      )

    ninth_surface =
      Helpers.resolve_surface_style("warm.*",
        default_background: "#FFFFFF",
        allow_palette_rotate: true,
        palette_index: 8
      )

    assert first_surface.background == "#FDE68A"
    assert eighth_surface.background == "#FDE68A"
    assert ninth_surface.background == "#FCD34D"
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

  test "normalizes distribution path aggregation options" do
    assert Helpers.normalize_distribution_path_aggregation("sum") == "sum"
    assert Helpers.normalize_distribution_path_aggregation("avg") == "mean"
    assert Helpers.normalize_distribution_path_aggregation("MEAN") == "mean"
    assert Helpers.normalize_distribution_path_aggregation("unknown") == "none"
  end

  test "normalizes heatmap color mode and config" do
    config =
      Helpers.normalize_heatmap_color_config(
        %{
          "single_color" => "#14b8a6",
          "palette_id" => "warm",
          "negative_color" => "#0ea5e9",
          "positive_color" => "#ef4444",
          "center_value" => "5.5",
          "symmetric" => "false"
        },
        "#22c55e"
      )

    config_no_symmetric =
      Helpers.normalize_heatmap_color_config(
        %{
          "single_color" => "#14b8a6",
          "palette_id" => "warm",
          "negative_color" => "#0ea5e9",
          "positive_color" => "#ef4444",
          "center_value" => "5.5"
        },
        "#22c55e"
      )

    assert Helpers.normalize_heatmap_color_mode("single") == "single"
    assert Helpers.normalize_heatmap_color_mode("unknown") == "auto"
    assert config["single_color"] == "#14B8A6"
    assert config["palette_id"] == "warm"
    assert config["negative_color"] == "#0EA5E9"
    assert config["positive_color"] == "#EF4444"
    assert config["center_value"] == 5.5
    refute config["symmetric"]
    assert config_no_symmetric["symmetric"]
  end

  test "preserves custom string buckets for both distribution axes" do
    existing = %{
      "designators" => %{
        "horizontal" => %{"type" => "custom", "buckets" => [10.0, 20.0]},
        "vertical" => %{"type" => "custom", "buckets" => [100.0, 200.0]}
      }
    }

    updated =
      Helpers.normalize_distribution_designators(
        %{
          "dist_designator_type" => "custom",
          "dist_designator_buckets" => "kg_0_5, kg_1_0, kg_1_5",
          "dist_v_designator_type" => "custom",
          "dist_v_designator_buckets" => "aed_100, aed_200"
        },
        existing
      )

    assert updated["horizontal"]["buckets"] == ["kg_0_5", "kg_1_0", "kg_1_5"]
    assert updated["vertical"]["buckets"] == ["aed_100", "aed_200"]

    updated_vertical_only =
      Helpers.normalize_distribution_designators(
        %{
          "dist_v_designator_type" => "custom",
          "dist_v_designator_buckets" => "aed_500, aed_1000"
        },
        %{"designators" => updated}
      )

    assert updated_vertical_only["horizontal"]["buckets"] == ["kg_0_5", "kg_1_0", "kg_1_5"]
    assert updated_vertical_only["vertical"]["buckets"] == ["aed_500", "aed_1000"]
  end

  test "sanitizes unsafe html payload for text widgets" do
    html =
      """
      <div onclick="alert(1)">
        <script>alert('x')</script>
        <a href="javascript:alert(1)" target="_blank">bad</a>
        <a href="https://example.com" target="_blank">good</a>
      </div>
      """

    sanitized = Helpers.sanitize_text_widget_html(html)

    refute String.contains?(sanitized, "<script")
    refute String.contains?(sanitized, "onclick=")
    refute String.contains?(sanitized, "javascript:")
    assert String.contains?(sanitized, ~s(href="https://example.com"))
    assert String.contains?(sanitized, ~s(target="_blank"))
    assert String.contains?(sanitized, ~s(rel="nofollow noopener noreferrer"))
  end

  test "removes disallowed tags but preserves inner text" do
    html = "<p>Hello <img src=x onerror=alert(1)>world</p>"
    sanitized = Helpers.sanitize_text_widget_html(html)

    assert String.contains?(sanitized, "<p>")
    assert String.contains?(sanitized, "Hello world")
    refute String.contains?(sanitized, "<img")
  end
end
