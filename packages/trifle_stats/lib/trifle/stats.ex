defmodule Trifle.Stats do
  @moduledoc """
  Documentation for `Trifle.Stats`.
  """

  @doc """
  Track function to run icremental stats.

  ## Examples
      iex> Trifle.Stats.track('test', DateTime.utc_now(), { duration: 103, count: 1})
      {:ok, [...]}
  """
  def track(key, at, values, config \\ nil) do
    Trifle.Stats.Operations.Timeseries.Increment.perform(
      key, at, values, config
    )
  end

  @doc """
  Assert function to run set stats.

  ## Examples
      iex> Trifle.Stats.assert('test', DateTime.utc_now(), { duration: 103, count: 1})
      {:ok, [...]}
  """
  def assert(key, at, values, config \\ nil) do
    Trifle.Stats.Operations.Timeseries.Set.perform(
      key, at, values, config
    )
  end

  @doc """
  Values function to retrieve stats.

  ## Examples
      iex> Trifle.Stats.values('test', DateTime.utc_now(), DateTime.utc_now(), :day)
      {:ok, [...]}
  """
  def values(key, from, to, range, config \\ nil) do
    Trifle.Stats.Operations.Timeseries.Values.perform(
      key, from, to, range, config
    )
  end
end
