defmodule TrifleApp.Granularity do
  @moduledoc """
  Shared helpers for working with time granularities across components.
  """

  alias Trifle.Stats.Nocturnal.Parser

  @spec display_name(String.t() | atom()) :: String.t()
  def display_name(granularity) when is_atom(granularity) do
    granularity
    |> Atom.to_string()
    |> display_name()
  end

  def display_name(granularity) do
    parser = Parser.new(to_string(granularity))

    if Parser.valid?(parser) do
      unit_label =
        case parser.unit do
          :second -> pluralize("second", parser.offset)
          :minute -> pluralize("minute", parser.offset)
          :hour -> pluralize("hour", parser.offset)
          :day -> pluralize("day", parser.offset)
          :week -> pluralize("week", parser.offset)
          :month -> pluralize("month", parser.offset)
          :quarter -> pluralize("quarter", parser.offset)
          :year -> pluralize("year", parser.offset)
          _ -> nil
        end

      if unit_label do
        "#{parser.offset} #{unit_label}"
      else
        to_string(granularity)
      end
    else
      to_string(granularity)
    end
  rescue
    _ -> to_string(granularity)
  end

  @spec options([String.t() | atom()]) :: [%{value: String.t(), label: String.t()}]
  def options(granularities) do
    granularities
    |> List.wrap()
    |> Enum.map(&normalize_option/1)
    |> Enum.uniq_by(& &1.value)
  end

  defp normalize_option(value) do
    string_value = value |> to_string() |> String.trim()

    %{
      value: string_value,
      label: display_name(string_value),
      badge: string_value
    }
  end

  defp pluralize(unit, 1), do: unit
  defp pluralize(unit, _count), do: "#{unit}s"
end
