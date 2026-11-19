defmodule Trifle.Stats.MeasurementSummary do
  @moduledoc "Weighted summaries of populated measurement buckets."
  # Samples are {timestamp, sum, count}. Missing counters are not zero samples.
  def summarize(samples) do
    valid =
      samples
      |> Enum.map(fn {at, sum, count} -> {at, number(sum), number(count)} end)
      |> Enum.filter(fn {_, sum, count} -> is_number(sum) and is_number(count) and count > 0 end)
      |> Enum.sort_by(fn {at, _, _} -> sort_timestamp(at) end)

    {sum, count} = Enum.reduce(valid, {0, 0}, fn {_, s, c}, {ss, cc} -> {ss + s, cc + c} end)

    {latest_at, latest} =
      case List.last(valid) do
        {at, s, c} -> {at, s / c}
        nil -> {nil, nil}
      end

    %{average: if(count > 0, do: sum / count), latest: latest, latest_at: latest_at}
  end

  defp sort_timestamp(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond)

  defp sort_timestamp(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:microsecond)

  defp sort_timestamp(at), do: at

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp number(_), do: nil
end
