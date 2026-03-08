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

  test "tool_error preserves question and exclamation punctuation" do
    assert Progress.text(:tool_error, %{tool: "build_metric_dashboard", reason: "bad input?"}) ==
             "Issue encountered while running build_metric_dashboard: bad input?"

    assert Progress.text(:tool_error, %{tool: "build_metric_dashboard", reason: "try again!"}) ==
             "Issue encountered while running build_metric_dashboard: try again!"
  end

  test "tool_error safely formats non string-char terms" do
    text = Progress.text(:tool_error, %{tool: "build_metric_dashboard", reason: {:bad_input, [path: "metrics"]}})

    assert text =~ "{:bad_input, [path: \"metrics\"]}"
  end

  test "error safely formats nil and non string-char terms" do
    assert Progress.text(:error, %{reason: nil}) == "Chat error."

    text = Progress.text(:error, %{reason: {:bad_input, [path: "metrics"]}})
    assert text =~ "Chat error: {:bad_input, [path: \"metrics\"]}"
  end
end
