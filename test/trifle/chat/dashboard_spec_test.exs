defmodule Trifle.Chat.DashboardSpecTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.DashboardSpec

  test "exposes all supported widget types" do
    assert DashboardSpec.supported_types() == [
             "kpi",
             "timeseries",
             "category",
             "table",
             "text",
             "list",
             "distribution",
             "heatmap"
           ]

    assert DashboardSpec.supported_type?("timeseries")
    refute DashboardSpec.supported_type?("unknown")
  end

  test "returns prompt fragment with dashboard tool guidance" do
    prompt = DashboardSpec.prompt_fragment()

    assert prompt =~ "describe_dashboard_widgets"
    assert prompt =~ "build_metric_dashboard"
    assert prompt =~ "12-column GridStack"
    assert prompt =~ "Category widgets default to `bar`"
    assert prompt =~ "\"chart_type\":\"pie\""
    assert prompt =~ "`chart` and `style` are invalid"
    assert prompt =~ "Distribution and heatmap widgets are for histograms/buckets"
  end
end
