defmodule TrifleApp.ExploreCoreTest do
  use ExUnit.Case, async: true

  alias TrifleApp.ExploreCore

  describe "format_number/1" do
    test "preserves trailing zeros for whole-number suffixes" do
      assert ExploreCore.format_number(390_000_000) == "390m"
      assert ExploreCore.format_number(100_000_000) == "100m"
    end

    test "trims decimal zeros for suffixes" do
      assert ExploreCore.format_number(1_000_000) == "1m"
      assert ExploreCore.format_number(1_500_000) == "1.5m"
    end
  end
end
