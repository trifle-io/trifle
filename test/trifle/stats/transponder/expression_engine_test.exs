defmodule Trifle.Stats.Transponder.ExpressionEngineTest do
  use ExUnit.Case, async: true

  alias Trifle.Stats.Transponder.ExpressionEngine

  test "parses and evaluates basic arithmetic" do
    {:ok, ast} = ExpressionEngine.parse("a + b * c", ["x", "y", "z"])
    assert {:ok, result} = ExpressionEngine.evaluate(ast, %{"a" => 1, "b" => 2, "c" => 5})
    assert to_float(result) == 11.0
  end

  test "supports parentheses precedence" do
    {:ok, ast} = ExpressionEngine.parse("(a + b) * c", ["a", "b", "c"])
    assert {:ok, result} = ExpressionEngine.evaluate(ast, %{"a" => 1, "b" => 2, "c" => 7})
    assert to_float(result) == 21.0
  end

  test "supports functions" do
    {:ok, ast} = ExpressionEngine.parse("sum(a, b, c)", ["a", "b", "c"])
    assert {:ok, sum_result} = ExpressionEngine.evaluate(ast, %{"a" => 1, "b" => 2, "c" => 3})
    assert to_float(sum_result) == 6.0

    {:ok, ast2} = ExpressionEngine.parse("max(a, b, c)", ["a", "b", "c"])
    assert {:ok, max_result} = ExpressionEngine.evaluate(ast2, %{"a" => 1, "b" => 2, "c" => 3})
    assert to_float(max_result) == 3.0
  end

  test "errors on divide by zero" do
    {:ok, ast} = ExpressionEngine.parse("a / b", ["a", "b"])
    assert {:ok, nil} == ExpressionEngine.evaluate(ast, %{"a" => 10, "b" => 0})
  end

  test "errors on unknown variable" do
    assert {:error, %{message: "Unknown variable d."}} == ExpressionEngine.parse("d + 1", ["a"])
  end

  test "validates variable count against paths" do
    too_many_paths = Enum.map(1..30, &"p#{&1}")
    assert {:error, %{message: _}} = ExpressionEngine.validate(too_many_paths, "a + b")
  end

  defp to_float(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_float(value) when is_number(value), do: value * 1.0
end
