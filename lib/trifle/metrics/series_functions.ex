defmodule Trifle.Metrics.SeriesFunctions do
  @moduledoc """
  Registry and transformations for timeline formula functions.

  Inputs and outputs are aligned lists of samples. Missing buckets retain their
  positions and do not contribute to statistics.
  """

  alias Trifle.Metrics.Statistics

  @functions [
    %{
      name: "moving_avg",
      signature: "moving_avg(a, n)",
      parameter: :window,
      description: "Trailing mean over n buckets, including the current bucket."
    },
    %{
      name: "moving_median",
      signature: "moving_median(a, n)",
      parameter: :window,
      description: "Trailing median over n buckets; reduces the effect of spikes."
    },
    %{
      name: "ewma",
      signature: "ewma(a, alpha)",
      parameter: :alpha,
      description: "Weighted average with 0 < alpha <= 1; smaller alpha smooths more."
    },
    %{
      name: "trend_line",
      signature: "trend_line(a)",
      parameter: :none,
      description: "Linear regression over the selected time range."
    }
  ]

  def all, do: @functions
  def fetch(name), do: Enum.find(@functions, &(&1.name == name))

  def validate(%{parameter: :none}, [_input]), do: :ok

  def validate(%{parameter: :window}, [_input, {:number, n}])
      when is_number(n) and n > 0 and trunc(n) == n,
      do: :ok

  def validate(%{parameter: :alpha}, [_input, {:number, alpha}])
      when is_number(alpha) and alpha > 0 and alpha <= 1,
      do: :ok

  def validate(function, _args) do
    constraint =
      case function.parameter do
        :window -> "n must be a positive integer constant"
        :alpha -> "alpha must be a constant greater than 0 and at most 1"
        :none -> "expects one input"
      end

    {:error, %{message: "#{function.signature}: #{constraint}."}}
  end

  def apply(%{name: "moving_avg"}, values, _keys, [n]),
    do: rolling(values, trunc(n), :mean)

  def apply(%{name: "moving_median"}, values, _keys, [n]),
    do: rolling(values, trunc(n), :median)

  def apply(%{name: "ewma"}, values, _keys, [alpha]) do
    {result, _state} =
      Enum.map_reduce(values, nil, fn
        nil, state ->
          {nil, state}

        value, nil ->
          {value, value}

        value, state ->
          next = alpha * value + (1 - alpha) * state
          {next, next}
      end)

    result
  end

  def apply(%{name: "trend_line"}, values, keys, []) do
    points = Enum.zip(keys, values)
    numeric = Enum.reject(points, fn {_at, value} -> is_nil(value) end)

    case numeric do
      [_, _ | _] ->
        {origin, _} = hd(numeric)
        origin = timestamp(origin)
        xy = Enum.map(numeric, fn {at, value} -> {timestamp(at) - origin, value} end)
        count = length(xy)
        mean_x = Enum.sum(Enum.map(xy, &elem(&1, 0))) / count
        mean_y = Enum.sum(Enum.map(xy, &elem(&1, 1))) / count
        variance = Enum.sum(Enum.map(xy, fn {x, _} -> (x - mean_x) * (x - mean_x) end))
        covariance = Enum.sum(Enum.map(xy, fn {x, y} -> (x - mean_x) * (y - mean_y) end))

        if variance == 0 do
          Enum.map(values, fn _ -> nil end)
        else
          slope = covariance / variance

          Enum.map(points, fn
            {_at, nil} -> nil
            {at, _value} -> mean_y + slope * (timestamp(at) - origin - mean_x)
          end)
        end

      _ ->
        Enum.map(values, fn _ -> nil end)
    end
  end

  defp rolling(values, n, statistic) do
    {result, _state} =
      Enum.map_reduce(values, {:queue.new(), 0, 0.0, 0}, fn value, {queue, size, sum, count} ->
        queue = :queue.in(value, queue)
        size = size + 1
        sum = sum + (value || 0)
        count = count + if(is_number(value), do: 1, else: 0)

        {queue, size, sum, count} =
          if size > n do
            {{:value, removed}, queue} = :queue.out(queue)

            {queue, size - 1, sum - (removed || 0),
             count - if(is_number(removed), do: 1, else: 0)}
          else
            {queue, size, sum, count}
          end

        result =
          cond do
            is_nil(value) -> nil
            statistic == :mean -> sum / count
            true -> queue |> :queue.to_list() |> Enum.filter(&is_number/1) |> Statistics.median()
          end

        {result, {queue, size, sum, count}}
      end)

    result
  end

  defp timestamp(%DateTime{} = at), do: DateTime.to_unix(at, :microsecond) / 1_000_000
  defp timestamp(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> timestamp()
  defp timestamp(at) when is_number(at), do: at
end
