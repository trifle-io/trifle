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

  test "normalizes visual alias rows by trimming and ignoring incomplete rows" do
    params = %{
      "series_alias_key" => %{"0" => " seller1 ", "1" => "seller2", "2" => "", "3" => "seller3"},
      "series_alias_value" => %{"0" => " me ", "1" => "", "2" => "ignored", "3" => " test "}
    }

    assert SeriesAliases.normalize_visual_params(params) == %{
             "seller1" => "me",
             "seller3" => "test"
           }
  end

  test "visual rows include existing aliases and one trailing blank row" do
    rows =
      SeriesAliases.visual_rows(%{"series_aliases" => %{"seller2" => "test", "seller1" => "me"}})

    assert [
             %{"index" => 0, "key" => "seller1", "value" => "me"},
             %{"index" => 1, "key" => "seller2", "value" => "test"},
             %{"index" => 2, "key" => "", "value" => ""}
           ] = rows
  end
end
