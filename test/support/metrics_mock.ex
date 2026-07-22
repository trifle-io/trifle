defmodule Trifle.MetricsMock do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> default_state() end, name: __MODULE__)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> default_state() end)
  end

  def stub_fetch_series(result_or_fun) do
    Agent.update(__MODULE__, fn state ->
      %{state | fetch_series: callable_6(result_or_fun)}
    end)
  end

  def stub_track(result_or_fun) do
    Agent.update(__MODULE__, fn state -> %{state | track: callable_5(result_or_fun)} end)
  end

  def stub_assert(result_or_fun) do
    Agent.update(__MODULE__, fn state -> %{state | assert: callable_5(result_or_fun)} end)
  end

  def calls do
    Agent.get(__MODULE__, fn state ->
      %{
        fetch_series: state.fetch_series_calls,
        track: state.track_calls,
        assert: state.assert_calls
      }
    end)
  end

  def fetch_series(source, key, from, to, granularity, opts \\ []) do
    fun =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.fetch_series, %{state | fetch_series_calls: state.fetch_series_calls + 1}}
      end)

    fun.(source, key, from, to, granularity, opts)
  end

  def track(key, at, values, stats_config, opts \\ []) do
    fun =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.track, %{state | track_calls: state.track_calls + 1}}
      end)

    fun.(key, at, values, stats_config, opts)
  end

  def assert(key, at, values, stats_config, opts \\ []) do
    fun =
      Agent.get_and_update(__MODULE__, fn state ->
        {state.assert, %{state | assert_calls: state.assert_calls + 1}}
      end)

    fun.(key, at, values, stats_config, opts)
  end

  defp default_state do
    %{
      fetch_series: fn _source, _key, _from, _to, _granularity, _opts ->
        {:ok, %{series: %{at: [], values: []}}}
      end,
      track: fn _key, _at, _values, _stats_config, _opts -> :ok end,
      assert: fn _key, _at, _values, _stats_config, _opts -> :ok end,
      fetch_series_calls: 0,
      track_calls: 0,
      assert_calls: 0
    }
  end

  defp callable_6(fun) when is_function(fun, 6), do: fun

  defp callable_6(value) do
    fn _a, _b, _c, _d, _e, _f -> value end
  end

  defp callable_5(fun) when is_function(fun, 5), do: fun

  defp callable_5(value) do
    fn _a, _b, _c, _d, _e -> value end
  end
end
