defmodule TrifleApp.TimeframeParsing.Url do
  @moduledoc """
  URL parameter parsing utilities for timeframe handling.
  """
  
  alias TrifleApp.TimeframeParsing
  
  @doc """
  Parses URL parameters to extract timeframe information.
  
  Returns {from, to, granularity, smart_timeframe_input, use_fixed_display}
  """
  def parse_url_params(params, config, available_granularities) do
    granularity = params["granularity"] || Enum.at(available_granularities, 3, "1h")
    
    {from, to, smart_input, use_fixed_display} =
      cond do
        # If we have explicit from/to parameters, use them (they take precedence)
        params["from"] && params["from"] != "" && params["to"] && params["to"] != "" ->
          case {TimeframeParsing.parse_date(params["from"], config.time_zone), TimeframeParsing.parse_date(params["to"], config.time_zone)} do
            {{:ok, from}, {:ok, to}} ->
              smart_input = if params["timeframe"] && params["timeframe"] != "" do
                params["timeframe"]
              else
                TimeframeParsing.detect_shorthand_from_range(from, to, config)
              end
              use_fixed_display = params["timeframe"] && params["timeframe"] != ""
              {from, to, smart_input, use_fixed_display}
            _ ->
              # If parsing fails, fall back to timeframe or defaults
              get_fallback_timeframe(params, config)
          end
        
        # If we have a timeframe parameter, use it
        params["timeframe"] && params["timeframe"] != "" ->
          case TimeframeParsing.parse_smart_timeframe(params["timeframe"], config) do
            {:ok, from, to, smart_input, use_fixed} -> {from, to, smart_input, use_fixed}
            {:error, _} -> get_default_timeframe(config)
          end
        
        # No parameters, use default 24h
        true ->
          get_default_timeframe(config)
      end
    
    {from, to, granularity, smart_input, use_fixed_display}
  end
  
  defp get_fallback_timeframe(params, config) do
    cond do
      params["timeframe"] && params["timeframe"] != "" ->
        case TimeframeParsing.parse_smart_timeframe(params["timeframe"], config) do
          {:ok, from, to, smart_input, use_fixed} -> {from, to, smart_input, use_fixed}
          {:error, _} -> get_default_timeframe(config)
        end
      true ->
        get_default_timeframe(config)
    end
  end
  
  defp get_default_timeframe(config) do
    to = DateTime.utc_now() |> DateTime.shift_zone!(config.time_zone || "UTC")
    from = DateTime.add(to, -24 * 60 * 60, :second)
    {from, to, "24h", false}
  end
end