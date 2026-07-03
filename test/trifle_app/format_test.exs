defmodule TrifleApp.FormatTest do
  use ExUnit.Case, async: true

  alias TrifleApp.Format

  describe "duration_us/1" do
    test "returns nil for nil" do
      assert Format.duration_us(nil) == nil
    end

    test "picks a unit by magnitude" do
      assert Format.duration_us(850) == "850μs"
      assert Format.duration_us(12_000) == "12ms"
      assert Format.duration_us(3_000_000) == "3s"
      assert Format.duration_us(120_000_000) == "2m"
    end
  end

  describe "duration_seconds/1" do
    test "returns nil for nil" do
      assert Format.duration_seconds(nil) == nil
    end

    test "formats sub-minute durations as seconds" do
      assert Format.duration_seconds(0) == "0s"
      assert Format.duration_seconds(45) == "45s"
    end

    test "formats minute durations with zero-padded seconds" do
      assert Format.duration_seconds(65) == "1m05s"
      assert Format.duration_seconds(185) == "3m05s"
      assert Format.duration_seconds(600) == "10m00s"
    end
  end
end
