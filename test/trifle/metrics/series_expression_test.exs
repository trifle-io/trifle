defmodule Trifle.Metrics.SeriesExpressionTest do
  use ExUnit.Case, async: true

  alias Trifle.Metrics.SeriesExpression

  defp calculate(expression, values, opts \\ []) do
    keys = Keyword.get(opts, :keys, Enum.to_list(0..(length(values) - 1)))
    {:ok, ast} = SeriesExpression.parse(expression, 1)
    samples = SeriesExpression.evaluate(ast, keys, %{"a" => Map.new(Enum.zip(keys, values))})
    Enum.map(keys, &Map.get(samples, &1))
  end

  test "trailing means use partial windows and count missing buckets" do
    assert calculate("moving_avg(a, 3)", [2, 4, nil, 10, 20]) == [2, 3, nil, 7, 15]
    assert calculate("moving_avg(a, 1)", [nil, 4, nil, 10]) == [nil, 4, nil, 10]
    assert calculate("moving_avg(a, 100)", [2, 4]) == [2, 3]
    assert calculate("moving_avg(a, 2)", [nil, nil, 6]) == [nil, nil, 6]
  end

  test "rolling medians handle spikes, even windows, and gaps" do
    assert calculate("moving_median(a, 3)", [1, 2, 100, 3, 4]) == [1, 1.5, 2, 3, 4]
    assert calculate("moving_median(a, 2)", [2, nil, 10, 20]) == [2, nil, 10, 15]
  end

  test "EWMA is seeded by the first value and retains state across gaps" do
    assert calculate("ewma(a, 0.5)", [nil, 2, 4, nil, 10]) == [nil, 2, 3, nil, 6.5]
    assert calculate("ewma(a, 1)", [2, nil, 4]) == [2, nil, 4]
  end

  test "regression uses actual elapsed time and preserves gaps" do
    at = ~U[2025-01-01 00:00:00Z]
    keys = Enum.map([0, 60, 180, 240], &DateTime.add(at, &1, :second))
    assert calculate("trend_line(a)", [1, 3, 7, nil], keys: keys) == [1, 3, 7, nil]
    assert calculate("trend_line(a)", [nil, 5, nil]) == [nil, nil, nil]
    assert calculate("trend_line(a)", [4, 4, 4]) == [4, 4, 4]

    fitted = calculate("trend_line(a)", [1, 2, 5])

    for {actual, expected} <- Enum.zip(fitted, [2 / 3, 8 / 3, 14 / 3]) do
      assert_in_delta actual, expected, 1.0e-10
    end
  end

  test "functions compose with arithmetic, scalar functions and temporal functions" do
    assert calculate("moving_avg(a * 10, 2) / 2", [2, 4, 6]) == [10, 15, 25]
    assert calculate("ewma(moving_avg(a, 2), 0.5)", [2, 4, 6]) == [2, 2.5, 3.75]
    assert calculate("sum(moving_avg(a, 2), ewma(a, 0.5))", [2, 4, 6]) == [4, 6, 9.5]
    assert calculate("-moving_avg(a, 2)", [2, 4]) == [-2, -3]
  end

  test "scalar semantics including Decimal, nil and zero division remain unchanged" do
    assert calculate("mean(a, 2)", [Decimal.new(4), nil, 8]) == [3, nil, 5]
    assert calculate("a / 0", [2, nil, 4]) == [nil, nil, nil]
    assert calculate("sqrt(a)", [4, 9]) == [2, 3]
  end

  test "invalid parameters and malformed formulas return useful errors" do
    for expression <- [
          "moving_avg(a, 0)",
          "moving_avg(a, -1)",
          "moving_avg(a, 1.5)",
          "moving_avg(a, a)",
          "moving_avg(a)",
          "ewma(a, 0)",
          "ewma(a, 1.1)",
          "trend_line(a, 2)",
          "unknown(a)",
          "sqrt(a, 2)",
          "a b",
          "moving_avg(b, 2)"
        ] do
      assert {:error, %{message: message}} = SeriesExpression.parse(expression, 1)
      assert is_binary(message)
    end
  end

  test "temporal functions are rejected in non-timeline contexts even when nested" do
    for context <- [:category, :distribution_values, :distribution_points] do
      assert {:error, %{message: message}} =
               SeriesExpression.parse("sum(a, moving_avg(a, 5))", 1, context)

      assert message =~ "requires timeline data"
      assert {:ok, _} = SeriesExpression.parse("mean(a, 2)", 1, context)
    end
  end

  test "empty and all-missing inputs are safe" do
    for expression <- ["moving_avg(a, 5)", "moving_median(a, 5)", "ewma(a, 0.3)", "trend_line(a)"] do
      {:ok, ast} = SeriesExpression.parse(expression, 1)
      assert SeriesExpression.evaluate(ast, [], %{"a" => %{}}) == %{}
      assert calculate(expression, [nil, nil]) == [nil, nil]
    end
  end
end
