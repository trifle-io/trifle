defmodule Trifle.DatabasePools.LimitsTest do
  use ExUnit.Case, async: true

  alias Trifle.DatabasePools.Limits

  test "uses valid sizes as given" do
    assert Limits.pool_size(3) == 3
    assert Limits.pool_size("7") == 7
    assert Limits.pool_size(" 4 ") == 4
  end

  test "clamps to the tenant maximum" do
    assert Limits.pool_size(500) == Limits.max_pool_size()
    assert Limits.pool_size("100000") == Limits.max_pool_size()
  end

  test "falls back to the default for missing, junk or non-positive values" do
    for value <- [nil, "", "abc", "5; DROP", "1.5", 0, -3, "-2", %{}, [1]] do
      assert Limits.pool_size(value) == Limits.default_pool_size(),
             "expected default for #{inspect(value)}"
    end
  end
end
