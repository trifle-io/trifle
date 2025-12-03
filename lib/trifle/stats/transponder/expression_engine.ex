defmodule Trifle.Stats.Transponder.ExpressionEngine do
  @moduledoc """
  Minimal expression parser/evaluator for transponders.

  Supports:
  - Binary operators: +, -, *, /
  - Parentheses for grouping
  - Numeric literals (ints/floats)
  - Auto-assigned variables (a, b, c, ...)
  - Simple n-ary functions: sum/mean/avg/min/max/sqrt

  The parser is intentionally small and self contained so it can later be moved
  into the trifle_stats plugin.
  """

  alias Trifle.Stats.Precision

  @letters Enum.map(?a..?z, &<<&1>>)

  def max_vars, do: length(@letters)

  def allowed_vars(count) when is_integer(count) and count >= 0 do
    Enum.take(@letters, count)
  end

  def validate(paths, expression) do
    with {:ok, normalized_paths} <- normalize_paths(paths),
         {:ok, _ast} <- parse(expression, normalized_paths) do
      :ok
    end
  end

  def parse(expression, paths) do
    var_list = allowed_vars(length(paths))

    with :ok <- ensure_within_var_limit(paths),
         {:ok, tokens} <- tokenize(expression),
         {:ok, {ast, []}} <- parse_expression(tokens, var_list) do
      {:ok, ast}
    end
  end

  def evaluate(ast, env) do
    do_eval(ast, env)
  end

  defp ensure_within_var_limit(paths) do
    if length(paths) > max_vars() do
      {:error, %{message: "Too many paths. Maximum supported is #{max_vars()}."}}
    else
      :ok
    end
  end

  defp normalize_paths(paths) when is_list(paths) do
    cleaned =
      paths
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      cleaned == [] -> {:error, %{message: "At least one path is required."}}
      length(cleaned) > max_vars() -> ensure_within_var_limit(cleaned)
      true -> {:ok, cleaned}
    end
  end

  defp normalize_paths(_), do: {:error, %{message: "Paths must be a list."}}

  # Tokenization --------------------------------------------------------------

  defp tokenize(expr) when is_binary(expr) do
    do_tokenize(String.trim(expr), [], 0)
  end

  defp tokenize(_), do: {:error, %{message: "Expression must be text."}}

  defp do_tokenize(<<>>, acc, _pos), do: {:ok, Enum.reverse(acc)}

  defp do_tokenize(<<" ", rest::binary>>, acc, pos), do: do_tokenize(rest, acc, pos + 1)
  defp do_tokenize(<<"\t", rest::binary>>, acc, pos), do: do_tokenize(rest, acc, pos + 1)
  defp do_tokenize(<<"\n", rest::binary>>, acc, pos), do: do_tokenize(rest, acc, pos + 1)
  defp do_tokenize(<<"\r", rest::binary>>, acc, pos), do: do_tokenize(rest, acc, pos + 1)

  for {op, token} <- [{"+", :+}, {"-", :-}, {"*", :*}, {"/", :/}, {"(", :"("}, {")", :")"}, {",", :","}] do
    defp do_tokenize(<<unquote(op), rest::binary>>, acc, pos),
      do: do_tokenize(rest, [unquote(token) | acc], pos + 1)
  end

  defp do_tokenize(<<c, _rest::binary>> = bin, acc, pos) when c in ?0..?9 do
    {number, rest, consumed} = read_number(bin, <<>>)
    token = {:number, number}
    do_tokenize(rest, [token | acc], pos + consumed)
  end

  defp do_tokenize(<<c, _rest::binary>> = bin, acc, pos) when c in ?A..?Z or c in ?a..?z or c == ?_ do
    {ident, rest, consumed} = read_ident(bin, <<>>)
    token = {:ident, ident}
    do_tokenize(rest, [token | acc], pos + consumed)
  end

  defp do_tokenize(_bin, _acc, pos) do
    {:error, %{message: "Invalid token at position #{pos}."}}
  end

  defp read_number(<<c, rest::binary>>, acc) when c in ?0..?9 do
    read_number(rest, <<acc::binary, c>>)
  end

  defp read_number(<<?., rest::binary>>, acc) do
    if String.contains?(acc, ".") do
      {parse_number(acc), rest, byte_size(acc)}
    else
      read_number(rest, <<acc::binary, ?.>>)
    end
  end

  defp read_number(rest, acc) do
    {parse_number(acc), rest, byte_size(acc)}
  end

  defp parse_number(bin) do
    case Float.parse(bin) do
      {value, ""} -> value
      _ -> 0
    end
  end

  defp read_ident(<<c, rest::binary>>, acc) when c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c == ?_ do
    read_ident(rest, <<acc::binary, c>>)
  end

  defp read_ident(rest, acc), do: {acc, rest, byte_size(acc)}

  # Parsing (recursive descent) ----------------------------------------------

  defp parse_expression(tokens, vars) do
    with {:ok, {term, rest}} <- parse_term(tokens, vars) do
      parse_expression_tail(term, rest, vars)
    end
  end

  defp parse_expression_tail(left, [op | rest], vars) when op in [:+, :-] do
    with {:ok, {right, rest2}} <- parse_term(rest, vars),
         {:ok, ast} <- {:ok, {op, left, right}} do
      parse_expression_tail(ast, rest2, vars)
    end
  end

  defp parse_expression_tail(ast, tokens, _vars), do: {:ok, {ast, tokens}}

  defp parse_term(tokens, vars) do
    with {:ok, {factor, rest}} <- parse_factor(tokens, vars) do
      parse_term_tail(factor, rest, vars)
    end
  end

  defp parse_term_tail(left, [op | rest], vars) when op in [:*, :/] do
    with {:ok, {right, rest2}} <- parse_factor(rest, vars),
         {:ok, ast} <- {:ok, {op, left, right}} do
      parse_term_tail(ast, rest2, vars)
    end
  end

  defp parse_term_tail(ast, tokens, _vars), do: {:ok, {ast, tokens}}

  defp parse_factor([:+ | rest], vars), do: parse_factor(rest, vars)

  defp parse_factor([:- | rest], vars) do
    with {:ok, {node, rest2}} <- parse_factor(rest, vars) do
      {:ok, {{:neg, node}, rest2}}
    end
  end

  defp parse_factor([{:number, n} | rest], _vars), do: {:ok, {{:number, n}, rest}}

  defp parse_factor([{:ident, ident}, :"(" | rest], vars) do
    with {:ok, {args, rest2}} <- parse_args(rest, vars) do
      {:ok, {{:func, ident, args}, rest2}}
    end
  end

  defp parse_factor([{:ident, ident} | rest], vars) do
    if ident in vars do
      {:ok, {{:var, ident}, rest}}
    else
      {:error, %{message: "Unknown variable #{ident}."}}
    end
  end

  defp parse_factor([:"(" | rest], vars) do
    with {:ok, {expr, rest2}} <- parse_expression(rest, vars) do
      case rest2 do
        [:")" | rest3] -> {:ok, {expr, rest3}}
        _ -> {:error, %{message: "Missing closing parenthesis."}}
      end
    end
  end

  defp parse_factor([], _vars), do: {:error, %{message: "Unexpected end of expression."}}
  defp parse_factor([unexpected | _], _vars), do: {:error, %{message: "Unexpected token #{inspect(unexpected)}."}}

  defp parse_args([:")" | rest], _vars), do: {:ok, {[], rest}}

  defp parse_args(tokens, vars) do
    with {:ok, {first, rest}} <- parse_expression(tokens, vars) do
      parse_args_tail([first], rest, vars)
    end
  end

  defp parse_args_tail(acc, [:"," | rest], vars) do
    with {:ok, {expr, rest2}} <- parse_expression(rest, vars) do
      parse_args_tail([expr | acc], rest2, vars)
    end
  end

  defp parse_args_tail(acc, [:")" | rest], _vars), do: {:ok, {Enum.reverse(acc), rest}}

  defp parse_args_tail(_acc, [], _vars), do: {:error, %{message: "Unclosed function arguments."}}

  defp parse_args_tail(_acc, [unexpected | _], _vars),
    do: {:error, %{message: "Unexpected token #{inspect(unexpected)} in arguments."}}

  # Evaluation ---------------------------------------------------------------

  defp do_eval({:number, n}, _env), do: {:ok, n}

  defp do_eval({:var, name}, env) do
    case Map.fetch(env, name) do
      {:ok, value} when is_number(value) -> {:ok, value}
      {:ok, %Decimal{} = value} -> {:ok, value}
      {:ok, nil} -> {:ok, nil}
      :error -> {:ok, nil}
      _ -> {:ok, nil}
    end
  end

  defp do_eval({:neg, expr}, env) do
    with {:ok, value} <- do_eval(expr, env) do
      {:ok, Precision.mult(value, -1)}
    end
  end

  defp do_eval({op, left, right}, env) when op in [:+, :-, :*, :/] do
    with {:ok, l} <- do_eval(left, env),
         {:ok, r} <- do_eval(right, env) do
      apply_binary(op, l, r)
    end
  end

  defp do_eval({:func, name, args}, env) do
    with {:ok, evaluated_args} <- eval_args(args, env),
         {:ok, result} <- apply_function(name, evaluated_args) do
      {:ok, result}
    end
  end

  defp eval_args(args, env) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
      case do_eval(arg, env) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      other -> other
    end
  end

  defp apply_binary(_op, nil, _), do: {:ok, nil}
  defp apply_binary(_op, _, nil), do: {:ok, nil}

  defp apply_binary(:+, l, r), do: {:ok, Precision.add(l, r)}
  defp apply_binary(:-, l, r), do: {:ok, Precision.sub(l, r)}
  defp apply_binary(:*, l, r), do: {:ok, Precision.mult(l, r)}

  defp apply_binary(:/, _l, 0), do: {:ok, nil}
  defp apply_binary(:/, l, r) do
    zero? =
      case r do
        0 -> true
        %Decimal{} = dec -> Decimal.equal?(dec, Decimal.new(0))
        _ -> false
      end

    if zero? do
      {:ok, nil}
    else
      {:ok, Precision.divide(l, r)}
    end
  end

  defp apply_function(name, args) when name in ["sum"] do
    cond do
      Enum.empty?(args) -> {:ok, nil}
      Enum.any?(args, &is_nil/1) -> {:ok, nil}
      true -> {:ok, Precision.sum(args)}
    end
  end

  defp apply_function(name, args) when name in ["mean", "avg"] do
    cond do
      Enum.empty?(args) -> {:ok, nil}
      Enum.any?(args, &is_nil/1) -> {:ok, nil}
      true ->
        numeric = Enum.map(args, &normalize_numeric/1)
        {:ok, Precision.average(numeric)}
    end
  end

  defp apply_function("max", args) do
    cond do
      Enum.empty?(args) -> {:ok, nil}
      Enum.any?(args, &is_nil/1) -> {:ok, nil}
      true ->
        numeric = Enum.map(args, &normalize_numeric/1)
        {:ok, Precision.max(numeric)}
    end
  end

  defp apply_function("sqrt", args) do
    case args do
      [value] ->
        {:ok, Precision.sqrt(value)}

      _ ->
        {:error, %{message: "Function sqrt expects 1 argument."}}
    end
  end

  defp apply_function("min", args) do
    cond do
      Enum.empty?(args) -> {:ok, nil}
      Enum.any?(args, &is_nil/1) -> {:ok, nil}
      true ->
        numeric = Enum.map(args, &normalize_numeric/1)
        {:ok, Precision.min(numeric)}
    end
  end

  defp apply_function(name, _args), do: {:error, %{message: "Unknown function #{name}."}}

  defp normalize_numeric(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp normalize_numeric(value) when is_number(value), do: value
  defp normalize_numeric(value), do: value
end
