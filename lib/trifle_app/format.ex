defmodule TrifleApp.Format do
  @moduledoc """
  Shared human-readable formatting helpers for LiveViews and components.
  """

  @doc """
  Formats a microsecond duration with an adaptive unit: "850μs", "12ms",
  "3s", "2m".
  """
  def duration_us(nil), do: nil

  def duration_us(microseconds) when is_integer(microseconds) do
    cond do
      microseconds < 1_000 ->
        "#{microseconds}μs"

      microseconds < 1_000_000 ->
        "#{div(microseconds, 1_000)}ms"

      microseconds < 60_000_000 ->
        "#{div(microseconds, 1_000_000)}s"

      true ->
        "#{div(microseconds, 60_000_000)}m"
    end
  end

  @doc """
  Formats a second duration as "45s" or "3m05s".
  """
  def duration_seconds(nil), do: nil

  def duration_seconds(seconds) when is_integer(seconds) and seconds >= 0 do
    if seconds < 60 do
      "#{seconds}s"
    else
      minutes = div(seconds, 60)
      remaining = rem(seconds, 60)
      "#{minutes}m#{pad_two(remaining)}s"
    end
  end

  @doc """
  Formats milliseconds as a compact duration, omitting zero units:
  "1d5h2m40s300ms", "30s", or "0ms".
  """
  def duration_ms(nil), do: nil
  def duration_ms(0), do: "0ms"

  def duration_ms(milliseconds) when is_integer(milliseconds) and milliseconds < 0,
    do: "-" <> duration_ms(-milliseconds)

  def duration_ms(milliseconds) when is_integer(milliseconds) do
    [{"d", 86_400_000}, {"h", 3_600_000}, {"m", 60_000}, {"s", 1_000}, {"ms", 1}]
    |> Enum.map_reduce(milliseconds, fn {unit, size}, remaining ->
      value = div(remaining, size)
      {if(value > 0, do: "#{value}#{unit}", else: ""), rem(remaining, size)}
    end)
    |> elem(0)
    |> Enum.join()
  end

  @doc "Formats milliseconds as a rounded value and adaptive unit for compact chart labels."
  def compact_duration_ms(nil), do: %{value: "—", unit: "ms"}

  def compact_duration_ms(%Decimal{} = milliseconds),
    do: milliseconds |> Decimal.to_float() |> compact_duration_ms()

  def compact_duration_ms(milliseconds) when is_number(milliseconds) do
    units = [{"ms", 1}, {"s", 1_000}, {"m", 60_000}, {"h", 3_600_000}, {"d", 86_400_000}]
    magnitude = abs(milliseconds)
    index = Enum.count(tl(units), fn {_, size} -> magnitude >= size end)
    {_, size} = Enum.at(units, index)
    rounded = Float.round(magnitude / size, 1)

    index =
      case Enum.at(units, index + 1) do
        {_, next_size} when rounded >= next_size / size -> index + 1
        _ -> index
      end

    {unit, size} = Enum.at(units, index)
    rounded = Float.round(milliseconds / size, 1)
    value = if rounded == trunc(rounded), do: to_string(trunc(rounded)), else: to_string(rounded)
    %{value: value, unit: unit}
  end

  defp pad_two(value) when value < 10, do: "0#{value}"
  defp pad_two(value), do: Integer.to_string(value)
end
