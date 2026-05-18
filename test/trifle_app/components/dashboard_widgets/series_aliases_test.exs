defmodule TrifleApp.Components.DashboardWidgets.SeriesAliasesTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Components.DashboardWidgets.SeriesAliases

  test "normalizes alias maps by trimming keys and values" do
    assert SeriesAliases.normalize(%{
             " seller1 " => " me ",
             "seller2" => "",
             "" => "ignored",
             "seller3" => 3
           }) == %{"seller1" => "me", "seller3" => "3"}
  end

  test "parses JSON object text" do
    assert {:ok, %{"seller1" => "me"}} =
             SeriesAliases.parse_text(~s({"seller1": "me"}))
  end

  test "rejects invalid JSON and non-object JSON" do
    assert {:error, "Aliases must be valid JSON."} = SeriesAliases.parse_text("{")
    assert {:error, "Aliases must be a JSON object."} = SeriesAliases.parse_text(~s(["seller1"]))
  end

  test "looks up exact candidates before dot leaf fallback" do
    aliases = %{"metrics.seller1" => "exact", "seller2" => "leaf"}

    assert SeriesAliases.lookup(aliases, ["metrics.seller1"]) == "exact"
    assert SeriesAliases.lookup(aliases, ["metrics.seller2"]) == "leaf"
  end
end
