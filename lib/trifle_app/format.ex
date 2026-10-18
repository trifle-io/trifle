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

  defp pad_two(value) when value < 10, do: "0#{value}"
  defp pad_two(value), do: Integer.to_string(value)
end
