defmodule Trifle.Stats.Transponder.ExpressionTest do
  use ExUnit.Case, async: true

  alias Trifle.Stats.Transponder.Expression

  test "applies expression across series values" do
    series = %{
      at: [1, 2, 3],
      values: [
        %{"metrics" => %{"a" => 2, "b" => 3}},
        %{"metrics" => %{"a" => 4, "b" => 5}},
        %{"metrics" => %{"a" => 6, "b" => 7}}
      ]
    }

    {:ok, updated} = Expression.transform(series, ["metrics.a", "metrics.b"], "a + b", "metrics.total")

    totals =
      updated.values
      |> Enum.map(fn %{"metrics" => m} -> m["total"] end)
      |> Enum.map(&to_float/1)

    assert totals == [5.0, 9.0, 13.0]
  end

  test "creates nested response paths when missing" do
    series = %{
      at: [1, 2],
      values: [
        %{"metrics" => %{"a" => 4, "b" => 2}},
        %{"metrics" => %{"b" => 1}}
      ]
    }

    {:ok, updated} =
      Expression.transform(series, ["metrics.a", "metrics.b"], "a / b", "metrics.duration.average")

    results =
      updated.values
      |> Enum.map(fn %{"metrics" => m} -> get_in(m, ["duration", "average"]) end)
      |> Enum.map(fn
        nil -> nil
        %Decimal{} = decimal -> Decimal.to_float(decimal)
        value when is_number(value) -> value * 1.0
      end)

    assert results == [2.0, nil]
  end

  test "returns error on missing value" do
    series = %{at: [1], values: [%{"metrics" => %{"a" => 2}}]}

    {:ok, updated} =
      Expression.transform(series, ["metrics.a", "metrics.b"], "a + b", "metrics.total")

    assert [%{"metrics" => %{"total" => nil}}] = updated.values
  end

  test "returns error on invalid response path" do
    series = %{at: [1], values: [%{"metrics" => %{"a" => 2, "b" => 3}}]}

    assert {:error, %{message: "Response path is required."}} ==
             Expression.transform(series, ["metrics.a", "metrics.b"], "a + b", " ")
  end

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_number(value), do: value * 1.0
end
