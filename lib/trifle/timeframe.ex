defmodule Trifle.Timeframe do
  @moduledoc """
  Helpers for validating and describing shorthand timeframe inputs such as "5m" or "2h".
  """

  alias Trifle.Stats.Nocturnal.Parser

  @error_message "Invalid timeframe. Use formats like 5m, 2h, 1d, 3w, 6mo, 1y."

  @type status :: :empty | {:ok, String.t()} | {:error, String.t()}

  @doc """
  Validates a shorthand timeframe string. Blank values are treated as valid.
  """
  @spec validate(term()) :: :ok | {:ok, Parser.t()} | {:error, String.t()}
  def validate(value) do
    case normalize(value) do
      "" ->
        :ok

      trimmed ->
        parse(trimmed)
    end
  end

  @doc """
  Describes a shorthand timeframe in human-readable form (e.g., "2 hours").
  """
  @spec describe(term()) :: status()
  def describe(value) do
    case validate(value) do
      :ok ->
        :empty

      {:ok, parser} ->
        {:ok, format_description(parser)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Returns a status tuple useful for rendering ("valid" vs "invalid") messaging.
  """
  @spec status(term()) :: status()
  def status(value), do: describe(value)

  @doc """
  Returns the default error message for invalid timeframe inputs.
  """
  def error_message, do: @error_message

  defp normalize(value) when value in [nil, ""], do: ""

  defp normalize(value) do
    value
    |> to_string()
    |> String.trim()
  end

  defp parse(string) when string in [nil, ""], do: :ok

  defp parse(string) do
    parser = Parser.new(string)

    if Parser.valid?(parser) do
      {:ok, parser}
    else
      {:error, @error_message}
    end
  rescue
    _ -> {:error, @error_message}
  end

  defp format_description(%Parser{offset: offset, unit: unit}) do
    "#{offset} #{pluralize(unit_label(unit), offset)}"
  end

  defp unit_label(:second), do: "second"
  defp unit_label(:minute), do: "minute"
  defp unit_label(:hour), do: "hour"
  defp unit_label(:day), do: "day"
  defp unit_label(:week), do: "week"
  defp unit_label(:month), do: "month"
  defp unit_label(:quarter), do: "quarter"
  defp unit_label(:year), do: "year"
  defp unit_label(other), do: Atom.to_string(other)

  defp pluralize(word, 1), do: word
  defp pluralize(word, _count), do: word <> "s"
end
