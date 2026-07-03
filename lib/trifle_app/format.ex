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

  defp pad_two(value) when value < 10, do: "0#{value}"
  defp pad_two(value), do: Integer.to_string(value)
end
