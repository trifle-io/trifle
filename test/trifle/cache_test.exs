defmodule Trifle.CacheTest do
  use ExUnit.Case, async: true

  alias Trifle.Cache

  defp unique_key, do: {:cache_test, System.unique_integer([:positive])}

  test "fetch runs the loader once and serves subsequent reads from cache" do
    key = unique_key()
    counter = :counters.new(1, [])

    loader = fn ->
      :counters.add(counter, 1, 1)
      :loaded
    end

    assert Cache.fetch(key, 60_000, loader) == :loaded
    assert Cache.fetch(key, 60_000, loader) == :loaded
    assert :counters.get(counter, 1) == 1
  end

  test "caches nil results" do
    key = unique_key()
    counter = :counters.new(1, [])

    loader = fn ->
      :counters.add(counter, 1, 1)
      nil
    end

    assert Cache.fetch(key, 60_000, loader) == nil
    assert Cache.fetch(key, 60_000, loader) == nil
    assert :counters.get(counter, 1) == 1
  end

  test "invalidate forces the next fetch to reload" do
    key = unique_key()

    assert Cache.fetch(key, 60_000, fn -> :first end) == :first
    assert :ok = Cache.invalidate(key)
    assert Cache.fetch(key, 60_000, fn -> :second end) == :second
  end

  test "entries expire after their ttl" do
    key = unique_key()

    assert Cache.fetch(key, 25, fn -> :first end) == :first
    Process.sleep(75)
    assert Cache.fetch(key, 25, fn -> :second end) == :second
  end
end
