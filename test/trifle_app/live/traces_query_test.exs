defmodule TrifleApp.TracesLive.QueryTest do
  use ExUnit.Case, async: true
  alias Trifle.Organizations.Database
  alias Trifle.Stats.Source
  alias TrifleApp.TracesLive.Query

  defp source,
    do:
      Source.from_database(%Database{id: "source", time_zone: "UTC", granularities: ["1h", "1d"]})

  test "parses filters and keeps a relative range stable across row and attribute selection" do
    params = %{
      "source_id" => "source",
      "timeframe" => "2d",
      "granularity" => "1h",
      "path" => "jobs",
      "state" => "error",
      "tags" => " default, scheduled,default ",
      "tag_mode" => "all",
      "duration_min" => "25"
    }

    assert {:ok, query} = Query.parse(params, source())
    assert query.filters[:tags] == %{all: ["default", "scheduled"]}
    assert query.filters[:segment] == "jobs"
    assert query.filters[:duration_min] == 25
    assert query.granularity == "1h"
    refute query.fixed

    assert {:ok, updated} =
             Query.parse(
               Map.merge(params, %{"reference" => "ref", "state" => "success"}),
               source(),
               query
             )

    assert updated.from == query.from
    assert updated.to == query.to
  end

  test "fixed ranges remain fixed and invalid ranges or durations fail safely" do
    params = %{"from" => "2026-09-01T00:00:00", "to" => "2026-09-02T00:00:00"}
    assert {:ok, %{fixed: true}} = Query.parse(params, source())

    for bad <- [%{"from" => "bad"}, %{"to" => "2026-08-01T00:00:00"}, %{"duration_min" => "-1"}] do
      assert {:error, _} = Query.parse(Map.merge(params, bad), source())
    end

    assert {:ok, %{granularity: "1h"}} = Query.parse(%{"granularity" => "unknown"}, source())
  end

  test "URL parameters are allowlisted, bounded and safely encoded" do
    assert Query.params(%{
             "path" => ["jobs"],
             "cursor" => "untrusted",
             "state" => String.duplicate("x", 3000)
           }) == %{}

    params = %{"path" => "jobs/test.rb", "reference" => "a&b"}
    assert URI.decode_query(URI.parse(Query.url(params)).query) == params
  end

  test "expanded detail is a URL preference, never a storage filter or range change" do
    params = %{"source_id" => "source", "timeframe" => "1d", "reference" => "ref"}
    assert {:ok, original} = Query.parse(params, source())
    refute original.detail_expanded
    expanded_params = Map.put(params, "detail", "expanded")
    assert Query.params(expanded_params) == expanded_params
    assert {:ok, expanded} = Query.parse(expanded_params, source(), original)
    assert expanded.detail_expanded
    assert expanded.filters == original.filters
    assert expanded.from == original.from
    assert expanded.to == original.to
    assert URI.decode_query(URI.parse(Query.url(expanded_params)).query) == expanded_params
  end

  test "missing, malformed or unselected detail preferences fall back to split view" do
    for params <- [
          %{},
          %{"reference" => "ref", "detail" => "split"},
          %{"reference" => "ref", "detail" => "true"},
          %{"reference" => "ref", "detail" => ["expanded"]},
          %{"detail" => "expanded"},
          %{"reference" => "  ", "detail" => "expanded"}
        ] do
      normalized = Query.params(params)
      refute Map.has_key?(normalized, "detail")
      assert {:ok, query} = Query.parse(normalized, source())
      refute query.detail_expanded
    end
  end
end
