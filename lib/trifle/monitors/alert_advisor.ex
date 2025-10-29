defmodule Trifle.Monitors.AlertAdvisor do
  @moduledoc """
  Generates AI-assisted alert configuration recommendations by leveraging the
  existing OpenAI integration used for ChatLive. The advisor takes the
  monitor's configured metric series, prepares a concise payload for the
  current alert strategy, and asks OpenAI to propose sensible configuration
  values for the desired sensitivity variant.
  """

  require Logger
  alias Decimal
  alias Trifle.Chat.OpenAIClient
  alias Trifle.Monitors.Monitor
  alias Trifle.Stats.Series

  @type variant :: :conservative | :balanced | :sensitive
  @type strategy :: :threshold | :range | :hampel | :cusum

  @type recommendation :: %{
          settings: map(),
          summary: String.t() | nil,
          variant: variant(),
          strategy: strategy()
        }

  @max_points 200
  @max_payload_values 12
  @default_max_completion_tokens 4096
  @default_model "gpt-5"
  @default_ai_state "balanced"

  @variant_descriptions %{
    conservative:
      "Favor stability. Recommend values that avoid noise-triggered alerts even if they respond slowly.",
    balanced:
      "Balance responsiveness and noise handling. Provide values that detect meaningful changes without excessive alerts.",
    sensitive:
      "Favor fast detection. Recommend aggressive values that surface even subtle deviations, accepting higher alert volume."
  }

  @strategy_instructions %{
    threshold: """
    The alert fires when a single metric crosses a fixed boundary.
    Return `settings.threshold_value` (float) and `settings.threshold_direction`.
    `threshold_direction` must be either "above" or "below" to indicate whether the alert triggers on upward or downward movement.
    Pick a threshold that aligns with the requested sensitivity while staying realistic for the observed data range.
    """,
    range: """
    The alert fires when the metric leaves a safe band between two limits.
    Return `settings.range_min_value` and `settings.range_max_value` as floats.
    Ensure `range_min_value` < `range_max_value`. Use the requested sensitivity to control band tightness.
    """,
    hampel: """
    The alert uses Hampel outlier detection comparing each point to the rolling median plus K times MAD.
    Return integer `settings.hampel_window_size`, float `settings.hampel_k`, and float `settings.hampel_mad_floor`.
    Window size controls smoothing (larger = smoother). K controls deviation tolerance. MAD floor prevents zero variance collapse.
    """,
    cusum: """
    The alert accumulates deviations over time (CUSUM) to detect level shifts.
    Return float `settings.cusum_k` (drift allowance) and float `settings.cusum_h` (alarm threshold).
    K controls tolerated per-point drift. H controls cumulative shift before triggering.
    """
  }

  @doc """
  Generates an alert configuration recommendation for the given monitor.

  ## Options

    * `:strategy` - Overrides the analysis strategy (defaults to the monitor's current strategy)
    * `:variant` - Sensitivity variant (`:balanced` by default)
    * `:series` - The timeseries dataset to analyse (required)
    * `:client` - MFA or anonymous function to call OpenAI (defaults to `OpenAIClient.chat_completion/2`)
    * `:max_points` - Maximum datapoints to include in the prompt (defaults to #{@max_points})

  Returns `{:ok, recommendation}` on success or `{:error, reason}` otherwise.
  """
  @spec recommend(Monitor.t(), Series.t(), keyword()) ::
          {:ok, recommendation()} | {:error, term()}
  def recommend(%Monitor{} = monitor, %Series{} = series, opts \\ []) do
    strategy =
      opts
      |> Keyword.get(:strategy)
      |> normalize_strategy(monitor)

    variant =
      opts
      |> Keyword.get(:variant, @default_ai_state)
      |> normalize_variant()

    client = Keyword.get(opts, :client, &OpenAIClient.chat_completion/2)
    max_points = Keyword.get(opts, :max_points, @max_points)
    path = String.trim(to_string(monitor.alert_metric_path || ""))

    with runtime_api_key <- runtime_api_key(),
         model <- advisor_model(),
         max_tokens <- advisor_max_completion_tokens(),
         {:ok, strategy} <- ensure_supported_strategy(strategy),
         {:ok, variant} <- ensure_supported_variant(variant),
         :ok <- ensure_metric_path(path),
         {:ok, points} <- extract_series_points(series, path, max_points),
         {:ok, summary} <- summarise_points(points),
         {:ok, payload_map} <- build_prompt_payload(monitor, path, strategy, variant, summary, points),
         payload_json = Jason.encode!(payload_map),
         messages = build_messages(strategy, variant, payload_json, max_tokens),
         options = request_options(runtime_api_key, model, max_tokens),
         :ok <- log_prompt(monitor, strategy, variant, model, max_tokens, messages, payload_json),
         {:ok, response} <- client.(messages, options),
         :ok <- log_raw_response(monitor, strategy, variant, response),
         {:ok, data} <- parse_response(response),
         :ok <- log_parsed_response(monitor, strategy, variant, data),
         {:ok, normalized} <- normalize_output(strategy, data) do
      {:ok,
       %{
         settings: normalized.settings,
         summary: normalized.summary,
         variant: variant,
         strategy: strategy
       }}
    else
      {:error, reason} ->
        log_failure(monitor, strategy, variant, reason)
        {:error, reason}

      error ->
        log_failure(monitor, strategy, variant, error)
        {:error, error}
    end
  end

  def recommend(_, _, _), do: {:error, :unsupported_context}

  defp normalize_strategy(nil, %Monitor{alerts: [first | _]}) do
    first.analysis_strategy || :threshold
  rescue
    _ -> :threshold
  end

  defp normalize_strategy(nil, _monitor), do: :threshold

  defp normalize_strategy(strategy, _monitor) when is_binary(strategy) do
    strategy
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
  rescue
    _ -> :threshold
  end

  defp normalize_strategy(strategy, _monitor) when is_atom(strategy), do: strategy

  defp normalize_strategy(_, _), do: :threshold

  defp normalize_variant(variant) when is_atom(variant), do: variant

  defp normalize_variant(variant) when is_binary(variant) do
    variant
    |> String.trim()
    |> String.downcase()
    |> case do
      "conservative" -> :conservative
      "sensitive" -> :sensitive
      "balanced" -> :balanced
      _ -> :balanced
    end
  end

  defp normalize_variant(_), do: :balanced

  defp ensure_supported_strategy(strategy)
       when strategy in [:threshold, :range, :hampel, :cusum],
       do: {:ok, strategy}

  defp ensure_supported_strategy(_), do: {:error, :unsupported_strategy}

  defp ensure_supported_variant(variant)
       when variant in [:conservative, :balanced, :sensitive],
       do: {:ok, variant}

  defp ensure_supported_variant(_), do: {:error, :unsupported_variant}

  defp ensure_metric_path(""), do: {:error, :missing_metric_path}
  defp ensure_metric_path(_), do: :ok

  defp runtime_api_key do
    env_key =
      case System.get_env("OPENAI_API_KEY") do
        value when is_binary(value) ->
          value
          |> String.trim()
          |> case do
            "" -> nil
            trimmed -> trimmed
          end

        _ ->
          nil
      end

    env_key || OpenAIClient.api_key()
  end

  defp advisor_model do
    env_model =
      case System.get_env("OPENAI_ADVISOR_MODEL") do
        value when is_binary(value) ->
          value
          |> String.trim()
          |> case do
            "" -> nil
            trimmed -> trimmed
          end

        _ ->
          nil
      end

    config_model =
      Application.get_env(:trifle, __MODULE__, [])
      |> case do
        list when is_list(list) -> Keyword.get(list, :model)
        map when is_map(map) -> Map.get(map, :model)
        _ -> nil
      end

    env_model || config_model || @default_model
  end

  defp advisor_max_completion_tokens do
    env_value =
      System.get_env("OPENAI_ADVISOR_MAX_COMPLETION_TOKENS")
      |> parse_positive_integer()

    config_value =
      Application.get_env(:trifle, __MODULE__, [])
      |> case do
        list when is_list(list) -> Keyword.get(list, :max_completion_tokens)
        map when is_map(map) -> Map.get(map, :max_completion_tokens)
        _ -> nil
      end
      |> parse_positive_integer()

    env_value || config_value || @default_max_completion_tokens
  end

  defp parse_positive_integer(nil), do: nil

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_integer(value), do: nil

  defp parse_positive_integer(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed ->
        case Integer.parse(trimmed) do
          {int, ""} when int > 0 -> int
          _ -> nil
        end
    end
  end

  defp parse_positive_integer(_), do: nil

  defp request_options(nil, model, max_tokens) do
    [
      model: model,
      max_completion_tokens: max_tokens,
      response_format: %{"type" => "json_object"}
    ]
  end

  defp request_options(api_key, model, max_tokens) do
    [
      model: model,
      max_completion_tokens: max_tokens,
      response_format: %{"type" => "json_object"},
      api_key: api_key
    ]
  end

  defp log_prompt(monitor, strategy, variant, model, max_tokens, messages, payload) do
    {system_prompt, user_prompt} = extract_prompts(messages)

    Logger.debug(fn ->
      """
      [AlertAdvisor] Requesting recommendation
        monitor_id=#{monitor.id}
        strategy=#{strategy}
        variant=#{variant}
        model=#{model}
        max_completion_tokens=#{max_tokens}
        system_prompt=#{inspect(system_prompt)}
        user_prompt=#{inspect(user_prompt)}
        payload=#{payload}
      """
    end)

    :ok
  end

  defp log_raw_response(monitor, strategy, variant, response) do
    Logger.debug(fn ->
      """
      [AlertAdvisor] Raw OpenAI response
        monitor_id=#{monitor.id}
        strategy=#{strategy}
        variant=#{variant}
        response=#{inspect(response, limit: :infinity, pretty: true)}
      """
    end)

    :ok
  end

  defp log_parsed_response(monitor, strategy, variant, data) do
    Logger.debug(fn ->
      """
      [AlertAdvisor] Parsed OpenAI payload
        monitor_id=#{monitor.id}
        strategy=#{strategy}
        variant=#{variant}
        parsed=#{inspect(data, limit: :infinity, pretty: true)}
      """
    end)

    :ok
  end

  defp log_failure(monitor, strategy, variant, reason) do
    Logger.warning(fn ->
      """
      [AlertAdvisor] Recommendation failed
        monitor_id=#{monitor.id}
        strategy=#{strategy}
        variant=#{variant}
        reason=#{inspect(reason, limit: :infinity, pretty: true)}
      """
    end)
  end

  defp extract_prompts(messages) when is_list(messages) do
    system =
      messages
      |> Enum.filter(&(&1["role"] == "system"))
      |> Enum.map(& &1["content"])
      |> Enum.join("\n\n")

    user =
      messages
      |> Enum.filter(&(&1["role"] == "user"))
      |> Enum.map(& &1["content"])
      |> Enum.join("\n\n")

    {system, user}
  end

  defp extract_prompts(_), do: {nil, nil}

  defp extract_series_points(%Series{} = series, path, max_points) do
    callback = fn at, value ->
      with {:ok, dt} <- normalize_datetime(at),
           {:ok, val} <- to_float(value) do
        %{
          "at" => DateTime.to_iso8601(dt),
          "value" => val
        }
      else
        _ -> nil
      end
    end

    timeline =
      series
      |> Series.format_timeline(path, 1, callback)
      |> normalize_timeline(path)

    timeline
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1["at"], &<=/2)
    |> maybe_trim(max_points)
    |> case do
      [] -> {:error, :no_data}
      points -> {:ok, points}
    end
  end

  defp normalize_timeline(result, path) when is_map(result) do
    Map.get(result, path) ||
      (result |> Map.values() |> Enum.reject(&is_nil/1) |> List.first() || [])
  end

  defp normalize_timeline(result, _path) when is_list(result), do: result
  defp normalize_timeline(_other, _path), do: []

  defp maybe_trim(points, max_points) when length(points) <= max_points, do: points

  defp maybe_trim(points, max_points) do
    points
    |> Enum.reverse()
    |> Enum.take(max_points)
    |> Enum.reverse()
  end

  defp summarise_points(points) when is_list(points) and points != [] do
    values = Enum.map(points, & &1["value"])
    sorted = Enum.sort(values)
    count = length(values)
    sum = Enum.sum(values)

    %{
      "count" => count,
      "min" => Enum.min(values),
      "max" => Enum.max(values),
      "mean" => sum / count,
      "median" => percentile(sorted, 0.5),
      "p90" => percentile(sorted, 0.9),
      "p95" => percentile(sorted, 0.95),
      "latest" => values |> List.last(),
      "first" => values |> List.first(),
      "trend" =>
        case {List.first(values), List.last(values)} do
          {nil, _} -> nil
          {_, nil} -> nil
          {first, last} when first != 0 -> (last - first) / abs(first)
          {first, last} -> last - first
        end
    }
    |> normalize_numbers()
    |> then(&{:ok, &1})
  end

  defp summarise_points(_), do: {:error, :no_data}

  defp percentile(values, p) when values == [], do: nil

  defp percentile(values, p) do
    rank = (length(values) - 1) * p
    lower = Enum.at(values, floor(rank))
    upper = Enum.at(values, ceil(rank))
    weight = rank - Float.floor(rank)

    cond do
      is_number(lower) and is_number(upper) ->
        lower + (upper - lower) * weight

      is_number(lower) ->
        lower

      is_number(upper) ->
        upper

      true ->
        nil
    end
  end

  defp normalize_numbers(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_float(value) ->
        Map.put(acc, key, Float.round(value, 6))

      {key, value}, acc when is_number(value) ->
        Map.put(acc, key, value)

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp build_prompt_payload(monitor, path, strategy, variant, summary, points) do
    recent_values =
      points
      |> Enum.map(& &1["value"])
      |> Enum.reject(&is_nil/1)
      |> Enum.take(-@max_payload_values)

    payload = %{
      "monitor" => %{
        "id" => to_string(monitor.id || "new"),
        "name" => monitor.name,
        "metric_key" => monitor.alert_metric_key,
        "metric_path" => path,
        "timeframe" => monitor.alert_timeframe,
        "granularity" => monitor.alert_granularity
      },
      "strategy" => to_string(strategy),
      "variant" => to_string(variant),
      "summary" => summary,
      "recent_values" => recent_values
    }

    {:ok, payload}
  end

  defp build_messages(strategy, variant, payload_json, max_tokens) do
    variant_text = Map.fetch!(@variant_descriptions, variant)
    strategy_text = Map.get(@strategy_instructions, strategy, "")

    system = """
    You are an analytics assistant that proposes robust alert configuration values for metric monitoring.
    Always respond with a compact JSON object shaped as:
    {
      "settings": { ... strategy specific keys ... },
      "explanation": "short human summary (<= 160 chars)"
    }
    Do not include code fences or Markdown. Provide numeric values as plain numbers, not strings.
    Respond immediately with this JSON object only—no prose, no prefixes, no suffixes.
    Variant guidance: #{variant_text}
    Strategy guidance: #{strategy_text}
    """

    user =
      """
    Use the provided statistics and recent numeric values to recommend alert settings aligned with the requested strategy and sensitivity.
    Ensure the suggested configuration is realistic for the data distribution and keep the explanation under 160 characters.
    Provide only the JSON object described above; do not add wording before or after the JSON.

    #{payload_json}
    """

    [
      %{"role" => "system", "content" => system},
      %{"role" => "user", "content" => user}
    ]
  end

  defp parse_response(%{"choices" => [first | _]}) do
    content =
      get_in(first, ["message", "content"]) ||
        get_in(first, [:message, :content])

    with {:ok, raw} <- ensure_content(content),
         {:ok, json} <- decode_json(raw) do
      {:ok, json}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_response}
    end
  end

  defp parse_response(_), do: {:error, :invalid_response}

  defp ensure_content(content) when is_binary(content) and byte_size(content) > 0,
    do: {:ok, content}

  defp ensure_content(_), do: {:error, :empty_response}

  defp decode_json(content) do
    content
    |> String.trim()
    |> strip_code_fence()
    |> Jason.decode()
  end

  defp strip_code_fence("```json" <> rest) do
    rest
    |> String.trim_trailing("```")
    |> String.trim()
  end

  defp strip_code_fence("```" <> rest) do
    rest
    |> String.trim_trailing("```")
    |> String.trim()
  end

  defp strip_code_fence(content), do: content

  defp normalize_output(strategy, payload) do
    settings_map = extract_settings_map(payload)
    summary = payload |> flexible_get(["explanation"]) |> safe_string()

    case strategy do
      :threshold ->
        with {:ok, value} <- require_float(settings_map, ["threshold_value"]),
             {:ok, direction} <- require_direction(settings_map, ["threshold_direction"]) do
          {:ok,
           %{
             settings: %{
               "threshold_value" => value,
               "threshold_direction" => direction
             },
             summary: summary
           }}
        end

      :range ->
        with {:ok, min_value} <- require_float(settings_map, ["range_min_value"]),
             {:ok, max_value} <- require_float(settings_map, ["range_max_value"]) do
          {min, max} =
            if min_value <= max_value do
              {min_value, max_value}
            else
              {max_value, min_value}
            end

          {:ok,
           %{
             settings: %{
               "range_min_value" => min,
               "range_max_value" => max
             },
             summary: summary
           }}
        end

      :hampel ->
        with {:ok, window} <- require_positive_integer(settings_map, ["hampel_window_size"]),
             {:ok, k} <- require_positive_float(settings_map, ["hampel_k"]),
             {:ok, floor} <- require_non_negative_float(settings_map, ["hampel_mad_floor"]) do
          {:ok,
           %{
             settings: %{
               "hampel_window_size" => window,
               "hampel_k" => k,
               "hampel_mad_floor" => floor
             },
             summary: summary
           }}
        end

      :cusum ->
        with {:ok, k} <- require_non_negative_float(settings_map, ["cusum_k"]),
             {:ok, h} <- require_positive_float(settings_map, ["cusum_h"]) do
          {:ok,
           %{
             settings: %{
               "cusum_k" => k,
               "cusum_h" => h
             },
             summary: summary
           }}
        end

      _ ->
        {:error, :unsupported_strategy}
    end
  end

  defp extract_settings_map(payload) when is_map(payload) do
    flexible_get(payload, ["settings"]) ||
      payload
  end

  defp extract_settings_map(_), do: %{}

  defp require_float(map, path) do
    case flexible_get(map, path) do
      value when is_number(value) -> {:ok, Float.round(value * 1.0, 6)}
      value when is_binary(value) -> parse_float(value)
      _ -> {:error, {:missing_value, path}}
    end
  end

  defp require_positive_float(map, path) do
    with {:ok, value} <- require_float(map, path) do
      if value > 0 do
        {:ok, value}
      else
        {:error, {:invalid_value, path}}
      end
    end
  end

  defp require_non_negative_float(map, path) do
    with {:ok, value} <- require_float(map, path) do
      if value >= 0 do
        {:ok, value}
      else
        {:error, {:invalid_value, path}}
      end
    end
  end

  defp require_positive_integer(map, path) do
    case flexible_get(map, path) do
      value when is_integer(value) and value > 0 ->
        {:ok, value}

      value when is_number(value) and value > 0 ->
        {:ok, max(1, round(value))}

      value when is_binary(value) ->
        case Integer.parse(value) do
          {parsed, ""} when parsed > 0 -> {:ok, parsed}
          _ -> {:error, {:invalid_value, path}}
        end

      _ ->
        {:error, {:invalid_value, path}}
    end
  end

  defp require_direction(map, path) do
    case flexible_get(map, path) do
      value when is_binary(value) ->
        normalized =
          value
          |> String.trim()
          |> String.downcase()

        case normalized do
          "above" -> {:ok, "above"}
          "greater" -> {:ok, "above"}
          "over" -> {:ok, "above"}
          "below" -> {:ok, "below"}
          "under" -> {:ok, "below"}
          "less" -> {:ok, "below"}
          _ -> {:error, {:invalid_value, path}}
        end

      value when is_atom(value) ->
        require_direction(map, path ++ [Atom.to_string(value)])

      _ ->
        {:error, {:invalid_value, path}}
    end
  end

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> {:ok, Float.round(number, 6)}
      :error -> {:error, {:invalid_value, value}}
    end
  end

  defp flexible_get(map, [key | rest]) when is_map(map) do
    value =
      Map.get(map, key) ||
        Map.get(map, to_string(key)) ||
        case key do
          binary when is_binary(binary) ->
            atom =
              try do
                String.to_existing_atom(binary)
              rescue
                _ -> nil
              end

            if atom, do: Map.get(map, atom), else: nil

          atom when is_atom(atom) ->
            Map.get(map, Atom.to_string(atom))

          _ ->
            nil
        end

    case rest do
      [] -> value
      _ -> flexible_get(value, rest)
    end
  end

  defp flexible_get(value, []) when not is_map(value), do: value
  defp flexible_get(_map, _), do: nil

  defp safe_string(nil), do: nil

  defp safe_string(value) when is_binary(value),
    do: value |> String.trim() |> truncate(200)

  defp safe_string(_), do: nil

  defp truncate(value, max) when byte_size(value) <= max, do: value

  defp truncate(value, max) do
    value
    |> String.slice(0, max)
    |> String.trim_trailing()
  end

  defp normalize_datetime(%DateTime{} = dt), do: {:ok, dt}

  defp normalize_datetime(%NaiveDateTime{} = naive) do
    {:ok, DateTime.from_naive!(naive, "Etc/UTC")}
  rescue
    _ -> {:error, :invalid_timestamp}
  end

  defp normalize_datetime(value) when is_integer(value) do
    unit = if abs(value) > 9_999_999_999, do: :millisecond, else: :second
    {:ok, DateTime.from_unix!(value, unit)}
  rescue
    _ -> {:error, :invalid_timestamp}
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> {:ok, dt}
      _ -> {:error, :invalid_timestamp}
    end
  end

  defp normalize_datetime(_), do: {:error, :invalid_timestamp}

  defp to_float(%Decimal{} = decimal), do: {:ok, Decimal.to_float(decimal)}
  defp to_float(value) when is_number(value), do: {:ok, value * 1.0}

  defp to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {parsed, _} -> {:ok, parsed}
      :error -> {:error, :invalid_value}
    end
  end

  defp to_float(_), do: {:error, :invalid_value}
end
