defmodule TrifleApp.Components.DashboardWidgets.SeriesOrderTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.SeriesOrder

  test "normalizes visual priority rows by index" do
    assert SeriesOrder.normalize_priority_rows(%{
             "2" => "",
             "1" => " me ",
             "0" => " test "
           }) == ["test", "me"]
  end

  test "priority rows include existing values and one trailing blank row" do
    assert SeriesOrder.priority_rows(%{"series_priority" => ["test", "me"]}) == [
             %{"index" => 0, "value" => "test"},
             %{"index" => 1, "value" => "me"},
             %{"index" => 2, "value" => ""}
           ]
  end

  test "visual priority rows include first and last groups with blank rows" do
    assert SeriesOrder.priority_visual_rows(%{
             "series_priority" => ["test"],
             "series_priority_last" => ["other"]
           }) == %{
             first: [
               %{"index" => 0, "value" => "test", "group" => "first"},
               %{"index" => 1, "value" => "", "group" => "first"}
             ],
             last: [
               %{"index" => 2, "value" => "other", "group" => "last"},
               %{"index" => 3, "value" => "", "group" => "last"}
             ]
           }
  end

  test "normalizes visual priority rows by group" do
    items = %{"0" => " top ", "1" => " bottom ", "2" => "", "3" => " middle "}
    groups = %{"0" => "first", "1" => "last", "2" => "last", "3" => "first"}

    assert SeriesOrder.normalize_priority_rows(items, groups, "first") == ["top", "middle"]
    assert SeriesOrder.normalize_priority_rows(items, groups, "last") == ["bottom"]
  end

  test "sorts first priorities before normal series and last priorities after normal series" do
    items = [
      %{name: "delta"},
      %{name: "omega"},
      %{name: "alpha"},
      %{name: "beta"}
    ]

    widget = %{
      "series_sort" => "alpha",
      "series_priority" => ["beta"],
      "series_priority_last" => ["omega"]
    }

    assert Enum.map(SeriesOrder.sort_named_items(items, widget), & &1.name) == [
             "beta",
             "alpha",
             "delta",
             "omega"
           ]
  end

  test "first priority wins when a series is also listed as last priority" do
    items = [%{name: "alpha"}, %{name: "beta"}]

    widget = %{
      "series_sort" => "alpha",
      "series_priority" => ["beta"],
      "series_priority_last" => ["beta"]
    }

    assert Enum.map(SeriesOrder.sort_named_items(items, widget), & &1.name) == ["beta", "alpha"]
  end
end
