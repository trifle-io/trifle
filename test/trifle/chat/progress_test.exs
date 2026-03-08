defmodule Trifle.Chat.ProgressTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.Progress

  test "tool_error includes a readable reason" do
    assert Progress.text(:tool_error, %{tool: "build_metric_dashboard", reason: "grid must contain at least one widget"}) ==
             "Issue encountered while running build_metric_dashboard: grid must contain at least one widget."
  end

  test "tool_error truncates long reasons" do
    reason = String.duplicate("x", 220)
    text = Progress.text(:tool_error, %{tool: "build_metric_dashboard", reason: reason})

    assert text =~ "Issue encountered while running build_metric_dashboard:"
    assert text =~ "..."
    assert String.ends_with?(text, ".")
    assert String.length(text) < 220
  end
end
