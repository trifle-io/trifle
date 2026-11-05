defmodule Trifle.Metrics.Statistics do
  @moduledoc false

  def median(values) do
    sorted = Enum.sort(values)
    len = length(sorted)
    mid = div(len, 2)

    cond do
      len == 0 -> nil
      rem(len, 2) == 1 -> Enum.at(sorted, mid)
      true -> (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    end
  end
end
