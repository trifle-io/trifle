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
    timeseries_spec = DashboardSpec.widget_spec("timeseries")
    list_spec = DashboardSpec.widget_spec("list")

    assert prompt =~ "describe_dashboard_widgets"
    assert prompt =~ "build_metric_dashboard"
    assert prompt =~ "12-column GridStack"
    assert prompt =~ "Every metric widget uses `series`"
    assert prompt =~ "\"kind\":\"path\""
    assert prompt =~ "\"kind\":\"expression\""
    assert prompt =~ "`chart` and `style` are invalid"
    assert prompt =~ "Distribution and heatmap widgets are for histograms/buckets"

    assert DashboardSpec.required_one_of("kpi") == [["series"]]
    assert DashboardSpec.required_one_of("timeseries") == [["series"]]

    assert Enum.any?(timeseries_spec.supported_fields, &(&1.name == "series"))
    assert Enum.any?(list_spec.supported_fields, &(&1.name == "label_strategy"))
  end
end
