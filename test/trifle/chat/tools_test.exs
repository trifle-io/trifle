defmodule Trifle.Chat.ToolsTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.Tools
  alias Trifle.Stats.Series

  describe "__tabularize_for_test__/2" do
    test "returns columns and rows sorted chronologically" do
      series = series_fixture()

      assert %{"columns" => ["at", "data.orders", "data.revenue"], "rows" => rows} =
               Tools.__tabularize_for_test__(series)

      assert rows == [
               ["2024-01-01T00:00:00Z", 5, 12],
               ["2024-01-02T00:00:00Z", 7, nil]
             ]
    end

    test "filters columns when only_paths provided" do
      series = series_fixture()

      assert %{"columns" => ["at", "data.revenue"], "rows" => rows} =
               Tools.__tabularize_for_test__(series, only_paths: ["data.revenue"])

      assert rows == [
               ["2024-01-01T00:00:00Z", 12],
               ["2024-01-02T00:00:00Z", nil]
             ]
    end
  end

  describe "__subset_table_for_test__/2" do
    test "extracts requested paths and preserves timestamps" do
      table = Tools.__tabularize_for_test__(series_fixture())

      assert %{"columns" => ["at", "data.orders"], "rows" => rows} =
               Tools.__subset_table_for_test__(table, ["data.orders"])

      assert rows == [
               ["2024-01-01T00:00:00Z", 5],
               ["2024-01-02T00:00:00Z", 7]
             ]
    end

    test "returns nil when no matching columns found" do
      table = Tools.__tabularize_for_test__(series_fixture())

      assert Tools.__subset_table_for_test__(table, ["missing.path"]) == nil
    end
  end

  defp series_fixture do
    timestamps = [
      ~U[2024-01-01 00:00:00Z],
      ~U[2024-01-02 00:00:00Z]
    ]

    values = [
      %{
        "data" => %{
          "orders" => 5,
          "revenue" => 12
        }
      },
      %{
        "data" => %{
          "orders" => 7
        }
      }
    ]

    Series.new(%{at: timestamps, values: values})
  end
end
