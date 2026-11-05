defmodule Trifle.Metrics.SeriesExpression do
  @moduledoc """
  Formula parsing and evaluation for aligned series samples.

  Temporal nodes are evaluated once per binding, then substituted into the
  scalar AST. Arithmetic and scalar functions retain ExpressionEngine semantics.
  """

  alias Trifle.Metrics.SeriesFunctions
  alias Trifle.Stats.Transponder.ExpressionEngine

  @scalar_functions [
    %{name: "sum", signature: "sum(a, b, ...)", description: "Sum of the inputs at each point."},
    %{
      name: "mean",
      signature: "mean(a, b, ...)",
      description: "Mean of the inputs at each point."
    },
    %{name: "avg", signature: "avg(a, b, ...)", description: "Alias for mean."},
    %{name: "min", signature: "min(a, b, ...)", description: "Smallest input at each point."},
    %{name: "max", signature: "max(a, b, ...)", description: "Largest input at each point."},
    %{name: "sqrt", signature: "sqrt(a)", description: "Square root of each input value."}
  ]
  @scalar_names Enum.map(@scalar_functions, & &1.name)

  def functions(context \\ :timeline) do
    temporal = if context == :timeline, do: SeriesFunctions.all(), else: []
    Enum.map(@scalar_functions ++ temporal, &Map.take(&1, [:name, :signature, :description]))
  end

  def parse(expression, prior_count, context \\ :timeline) do
    paths = List.duplicate("path", prior_count)

    case ExpressionEngine.parse(expression, paths) do
      {:ok, ast} ->
        with :ok <- validate(ast, context), do: {:ok, ast}

      {:error, %{message: _} = error} ->
        {:error, error}

      _ ->
        {:error, %{message: "Invalid formula. Check operators and parentheses."}}
    end
  end

  def evaluate(ast, keys, bindings) do
    {scalar_ast, bindings} = materialize(ast, keys, bindings)

    Enum.into(keys, %{}, fn key ->
      env = Map.new(bindings, fn {name, samples} -> {name, Map.get(samples, key)} end)

      value =
        case ExpressionEngine.evaluate(scalar_ast, env) do
          {:ok, %Decimal{} = value} -> Decimal.to_float(value)
          {:ok, value} when is_number(value) -> value * 1.0
          _ -> nil
        end

      {key, value}
    end)
  end

  defp validate({:func, name, args}, context) do
    case SeriesFunctions.fetch(name) do
      nil ->
        cond do
          name not in @scalar_names ->
            {:error, %{message: "Unknown function #{name}."}}

          name == "sqrt" and length(args) != 1 ->
            {:error, %{message: "Function sqrt expects 1 argument."}}

          true ->
            validate_children(args, context)
        end

      function ->
        if context == :timeline do
          with :ok <- SeriesFunctions.validate(function, args),
               :ok <- validate_children(args, context),
               do: :ok
        else
          {:error,
           %{
             message:
               "Function #{name} requires timeline data; it is unavailable for category and distribution formulas."
           }}
        end
    end
  end

  defp validate({op, left, right}, context) when op in [:+, :-, :*, :/],
    do: validate_children([left, right], context)

  defp validate({:neg, child}, context), do: validate(child, context)
  defp validate({:number, value}, _context) when is_number(value), do: :ok
  defp validate({:var, name}, _context) when is_binary(name), do: :ok

  defp validate(_invalid, _context),
    do: {:error, %{message: "Invalid formula. Check operators and parentheses."}}

  defp validate_children(children, context) do
    Enum.reduce_while(children, :ok, fn child, :ok ->
      case validate(child, context) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp materialize({:func, name, args}, keys, bindings) do
    case SeriesFunctions.fetch(name) do
      nil ->
        {args, bindings} = Enum.map_reduce(args, bindings, &materialize(&1, keys, &2))
        {{:func, name, args}, bindings}

      function ->
        [input | params] = args
        samples = evaluate(input, keys, bindings)
        values = Enum.map(keys, &Map.get(samples, &1))
        params = Enum.map(params, fn {:number, value} -> value end)
        output = SeriesFunctions.apply(function, values, keys, params)
        name = "__timeline_#{map_size(bindings)}"
        {{:var, name}, Map.put(bindings, name, Map.new(Enum.zip(keys, output)))}
    end
  end

  defp materialize({op, left, right}, keys, bindings) when op in [:+, :-, :*, :/] do
    {left, bindings} = materialize(left, keys, bindings)
    {right, bindings} = materialize(right, keys, bindings)
    {{op, left, right}, bindings}
  end

  defp materialize({:neg, child}, keys, bindings) do
    {child, bindings} = materialize(child, keys, bindings)
    {{:neg, child}, bindings}
  end

  defp materialize(leaf, _keys, bindings), do: {leaf, bindings}
end
