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

  test "inspecting_metric_schema reports the schema sample descriptor" do
    assert Progress.text(:inspecting_metric_schema, %{metric_key: "sales", timeframe: "schema sample", granularity: "1d"}) ==
             "Inspecting metric schema (Metrics Key sales • schema sample • granularity 1d)."
  end

  test "fetching_timeseries reports safe granularity adjustments" do
    assert Progress.text(:fetching_timeseries, %{metric_key: "sales", timeframe: "60d", granularity: "1d", adjusted_from: "1m"}) ==
             "Fetching data for Metrics Key sales • 60d • granularity 1d • adjusted from 1m."
  end

  test "formatting_series reports dashboard granularity adjustments" do
    assert Progress.text(:formatting_series, %{metric_key: "sales", formatter: "dashboard", timeframe: "60d", granularity: "1d", adjusted_from: "1m"}) ==
             "Formatting series output (Dashboard formatter • Metrics Key sales • 60d • granularity 1d • adjusted from 1m)."
  end
end
