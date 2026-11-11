defmodule Trifle.Organizations.TokenCacheTest do
  use ExUnit.Case, async: true

  alias Trifle.Organizations.TokenCache

  defp key, do: :crypto.strong_rand_bytes(32)

  test "returns what was stored until it expires" do
    hash = key()

    assert TokenCache.get(hash) == :error
    assert TokenCache.put(hash, %{token: :payload}, 5_000) == :ok
    assert TokenCache.get(hash) == {:ok, %{token: :payload}}
  end

  test "expired entries are a miss" do
    hash = key()

    TokenCache.put(hash, :payload, 1)
    Process.sleep(5)

    assert TokenCache.get(hash) == :error
  end

  test "invalidate removes the entry" do
    hash = key()

    TokenCache.put(hash, :payload, 5_000)
    TokenCache.invalidate(hash)

    # invalidate is a cast; a call to the same process guarantees it was handled.
    _ = :sys.get_state(TokenCache)

    assert TokenCache.get(hash) == :error
  end

  test "reads do not go through the cache process" do
    hash = key()
    TokenCache.put(hash, :payload, 5_000)

    :sys.suspend(TokenCache)

    try do
      assert TokenCache.get(hash) == {:ok, :payload}
      assert TokenCache.put(key(), :other, 5_000) == :ok
    after
      :sys.resume(TokenCache)
    end
  end
end
