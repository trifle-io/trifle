defmodule Trifle.Metrics.ValuePath do
  @moduledoc false
  alias Trifle.Stats.Path

  def canonical(path), do: path |> Path.parse() |> Path.render()

  def prefix?(path, prefix) do
    prefix = Path.segments(prefix)
    Enum.take(Path.segments(path), length(prefix)) == prefix
  end

  def strip_wildcard(path) do
    parts = Path.parse(path)

    case List.last(parts) do
      %{wildcard: true} -> parts |> Enum.drop(-1) |> Path.render()
      _ -> Path.render(parts)
    end
  end

  def terminal_wildcard?(path) do
    parts = Path.parse(path)

    length(parts) > 1 and match?(%{wildcard: true}, List.last(parts)) and
      not Enum.any?(Enum.drop(parts, -1), & &1.unescaped_star)
  end

  def child_prefixes(path, available) do
    prefix = path |> strip_wildcard() |> Path.segments()
    size = length(prefix)

    available
    |> Enum.map(&Path.segments/1)
    |> Enum.filter(&(length(&1) > size and Enum.take(&1, size) == prefix))
    |> Enum.map(&(Enum.take(&1, size + 1) |> Path.join()))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Match concrete segments, so a literal dot cannot be mistaken for a boundary.
  # A terminal wildcard retains the app's existing capture-the-remainder behavior.
  def captures(pattern, concrete), do: capture(Path.parse(pattern), Path.segments(concrete), [])
  defp capture([], [], acc), do: {:ok, Enum.reverse(acc)}

  defp capture([%{wildcard: true}], [_ | _] = rest, acc),
    do: {:ok, Enum.reverse([Path.join(rest) | acc])}

  defp capture([%{wildcard: true} | pattern], [value | rest], acc),
    do: capture(pattern, rest, [Path.escape_segment(value) | acc])

  defp capture([%{value: value} | pattern], [value | rest], acc),
    do: capture(pattern, rest, acc)

  defp capture(_, _, _), do: :error

  # Table filters historically also allow partial globs. Only unescaped stars
  # become glob operators; escaped stars remain literal canonical path text.
  def glob_matches?(path, pattern) do
    regex = Regex.compile!("\\A" <> glob_regex(pattern) <> "\\z", "u")
    Regex.match?(regex, Path.join(Path.segments(path)))
  end

  defp glob_regex(<<>>), do: ""

  defp glob_regex(<<?\\, char, rest::binary>>) when char in [?\\, ?., ?*],
    do: Regex.escape(Path.escape_segment(<<char>>)) <> glob_regex(rest)

  defp glob_regex(<<?., rest::binary>>), do: "\\." <> glob_regex(rest)
  defp glob_regex(<<?*, rest::binary>>), do: ".*" <> glob_regex(rest)

  defp glob_regex(<<char::utf8, rest::binary>>),
    do: Regex.escape(Path.escape_segment(<<char::utf8>>)) <> glob_regex(rest)
end
