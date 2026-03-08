defmodule Trifle.Chat.DashboardToolsTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.Tools

  test "describe_dashboard_widgets returns the shared widget spec" do
    assert {:ok, %{status: "ok", widget_spec: spec, prompt_fragment: prompt}} =
             Tools.execute("describe_dashboard_widgets", "{}", %{})

    widget_types =
      spec.widgets
      |> Enum.map(& &1["type"])
      |> Enum.sort()

    assert "distribution" in widget_types
    assert "heatmap" in widget_types
    assert prompt =~ "build_metric_dashboard"
  end
end
