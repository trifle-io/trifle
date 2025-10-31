defmodule Trifle.Organizations.DashboardSegments do
  @moduledoc """
  Utilities for normalizing dashboard segment selections and resolving keys that
  depend on segment placeholders.
  """

  @capture_group_regex ~r/\((?:\\.|[^()])*\)/
  @noncapturing_prefixes ["?:", "?=", "?!", "?<=", "?<!"]

  @doc """
  Normalizes a map of segment selections by coercing keys and values to strings.
  Nil values are converted to the empty string.
  """
  @spec normalize_value_map(map() | nil) :: map()
  def normalize_value_map(nil), do: %{}

  def normalize_value_map(values) when is_map(values) do
    Enum.reduce(values, %{}, fn {key, value}, acc ->
      normalized_key = key |> to_string()

      normalized_value =
        cond do
          is_binary(value) -> value
          is_nil(value) -> ""
          true -> to_string(value)
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  def normalize_value_map(_other), do: %{}

  @doc """
  Computes the resolved segment selections given the dashboard segment definition,
  applying overrides (such as from the URL or a stored monitor) and previous values.

  Returns `{values_map, segments_with_current}` where `values_map` is a map of
  segment names to selected values, and `segments_with_current` is a list of segment
  definitions that include the `"current_value"` key.
  """
  @spec compute_state(list(), map(), map()) :: {map(), list()}
  def compute_state(segments, overrides \\ %{}, previous_values \\ %{}) when is_list(segments) do
    overrides = normalize_value_map(overrides)
    previous_values = normalize_value_map(previous_values)

    segments
    |> Enum.reduce({%{}, []}, fn segment, {values_acc, segments_acc} ->
      name = segment_name(segment)
      type = segment_type(segment)
      available_values = segment_select_values(segment)
      override_present? = Map.has_key?(overrides, name)
      override_value = Map.get(overrides, name)
      previous_present? = Map.has_key?(previous_values, name)
      previous_value = Map.get(previous_values, name)
      default_value = Map.get(segment, "default_value")

      {selected_value, resolved_default} =
        case type do
          "text" ->
            value =
              cond do
                override_present? -> sanitize_text_value(override_value)
                previous_present? -> sanitize_text_value(previous_value)
                not is_nil(default_value) -> sanitize_text_value(default_value)
                true -> ""
              end

            {value, sanitize_text_value(default_value)}

          _ ->
            resolved_default = resolve_default_value(default_value, available_values)

            selected =
              cond do
                override_present? ->
                  value = sanitize_select_value(override_value)

                  if value in available_values or available_values == [] do
                    value
                  else
                    fallback_select_value(
                      previous_present?,
                      previous_value,
                      resolved_default,
                      available_values
                    )
                  end

                previous_present? ->
                  value = sanitize_select_value(previous_value)

                  if value in available_values or available_values == [] do
                    value
                  else
                    fallback_select_value(false, nil, resolved_default, available_values)
                  end

                true ->
                  fallback_select_value(false, nil, resolved_default, available_values)
              end

            {selected, resolved_default}
        end

      updated_segment =
        segment
        |> Map.put("type", type)
        |> Map.put("default_value", resolved_default)
        |> Map.put("current_value", selected_value)

      {Map.put(values_acc, name, selected_value), [updated_segment | segments_acc]}
    end)
    |> then(fn {values, segments_rev} ->
      {values, Enum.reverse(segments_rev)}
    end)
  end

  def compute_state(_segments, _overrides, _previous), do: {%{}, []}

  @doc """
  Resolves a dashboard key pattern by substituting capture groups with the provided
  segment values. Returns the resolved key string, preserving nil and blank inputs.
  """
  @spec resolve_key(String.t() | nil, list(), map()) :: String.t() | nil
  def resolve_key(nil, _segments, _values), do: nil
  def resolve_key("", _segments, _values), do: ""

  def resolve_key(pattern, segments, values_map) when is_binary(pattern) do
    captures = extract_captures(pattern)

    if captures == [] do
      strip_regex_anchors(pattern)
    else
      values_map = normalize_value_map(values_map)
      ordered_names = Enum.map(segments, &segment_name/1)

      {values, _unused} =
        Enum.reduce(captures, {[], ordered_names}, fn capture, {acc_values, unused_names} ->
          {value, updated_unused} = capture_value_for_segment(capture, values_map, unused_names)
          {[value | acc_values], updated_unused}
        end)

      substituted = substitute_captures(pattern, captures, Enum.reverse(values))
      strip_regex_anchors(substituted)
    end
  end

  # Helpers --------------------------------------------------------------------

  defp segment_select_values(segment) do
    segment
    |> Map.get("groups", [])
    |> Enum.flat_map(fn group ->
      group
      |> Map.get("items", [])
      |> Enum.map(fn item -> sanitize_select_value(Map.get(item, "value")) end)
    end)
  end

  defp segment_name(segment) do
    segment
    |> Map.get("name")
    |> case do
      nil -> ""
      value -> value |> to_string() |> String.trim()
    end
  end

  defp segment_type(segment) do
    segment
    |> Map.get("type", "select")
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "text" -> "text"
      "select" -> "select"
      "dropdown" -> "select"
      other when other == "" -> "select"
      other -> other
    end
  end

  defp fallback_select_value(_previous_present?, _previous_value, default_value, available_values) do
    cond do
      default_value not in [nil, ""] and default_value in available_values -> default_value
      available_values != [] -> hd(available_values)
      default_value in [nil, ""] -> default_value || ""
      true -> sanitize_select_value(default_value)
    end
  end

  defp resolve_default_value(nil, available_values) do
    case available_values do
      [] -> ""
      [first | _] -> first
    end
  end

  defp resolve_default_value("", available_values) do
    if available_values == [] do
      ""
    else
      ""
    end
  end

  defp resolve_default_value(value, available_values) do
    sanitized = sanitize_select_value(value)

    cond do
      sanitized == "" -> ""
      sanitized in available_values -> sanitized
      available_values == [] -> sanitized
      true -> hd(available_values)
    end
  end

  defp sanitize_select_value(nil), do: ""
  defp sanitize_select_value(value) when is_binary(value), do: value
  defp sanitize_select_value(value), do: to_string(value)

  defp sanitize_text_value(nil), do: ""
  defp sanitize_text_value(value) when is_binary(value), do: value
  defp sanitize_text_value(value), do: to_string(value)

  defp capture_value_for_segment(%{name: name}, values_map, unused_names) do
    cond do
      name && Map.has_key?(values_map, name) ->
        value = Map.get(values_map, name, "")
        {value, delete_first(unused_names, name)}

      true ->
        case unused_names do
          [next_name | rest] -> {Map.get(values_map, next_name, ""), rest}
          [] -> {"", []}
        end
    end
  end

  defp capture_value_for_segment(_capture, values_map, unused_names) do
    case unused_names do
      [next_name | rest] -> {Map.get(values_map, next_name, ""), rest}
      [] -> {"", []}
    end
  end

  defp extract_captures(pattern) do
    Regex.scan(@capture_group_regex, pattern, return: :index)
    |> Enum.map(&hd/1)
    |> Enum.reduce({[], 0}, fn {start, length}, {acc, idx} ->
      match = binary_part(pattern, start, length)

      case classify_capture(match) do
        {:capturing, name} ->
          info = %{index: idx, start: start, length: length, name: name, raw: match}
          {[info | acc], idx + 1}

        :noncapturing ->
          {acc, idx}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp classify_capture(match) do
    inner = inner_capture_content(match)

    cond do
      String.starts_with?(inner, "?<") ->
        name = extract_group_name(inner, 2)
        {:capturing, name}

      String.starts_with?(inner, "?P<") ->
        name = extract_group_name(inner, 3)
        {:capturing, name}

      String.starts_with?(inner, "?") ->
        prefix = String.slice(inner, 1, 2)

        cond do
          prefix in @noncapturing_prefixes ->
            :noncapturing

          String.starts_with?(inner, "?<") ->
            name = extract_group_name(inner, 2)
            {:capturing, name}

          String.starts_with?(inner, "?P<") ->
            name = extract_group_name(inner, 3)
            {:capturing, name}

          true ->
            {:capturing, nil}
        end

      true ->
        {:capturing, nil}
    end
  end

  defp inner_capture_content(capture) do
    capture
    |> String.slice(1, max(byte_size(capture) - 2, 0))
  end

  defp extract_group_name(inner, prefix_length) do
    rest = String.slice(inner, prefix_length, byte_size(inner) - prefix_length)

    case String.split(rest, ">", parts: 2) do
      [name | _] -> String.trim(name)
      _ -> nil
    end
  end

  defp substitute_captures(pattern, captures, values) do
    {iodata, last_index} =
      Enum.zip(captures, values)
      |> Enum.reduce({[], 0}, fn {capture, value}, {parts, cursor} ->
        prefix_length = capture.start - cursor
        prefix = if prefix_length > 0, do: binary_part(pattern, cursor, prefix_length), else: ""

        {[parts | [prefix, value]], capture.start + capture.length}
      end)

    flat_parts = List.flatten(iodata)
    suffix_length = byte_size(pattern) - last_index
    suffix = if suffix_length > 0, do: binary_part(pattern, last_index, suffix_length), else: ""

    [flat_parts, suffix]
    |> IO.iodata_to_binary()
  end

  defp strip_regex_anchors(nil), do: nil

  defp strip_regex_anchors(value) when is_binary(value) do
    value
    |> strip_leading_anchor()
    |> strip_trailing_anchor()
  end

  defp strip_leading_anchor(""), do: ""
  defp strip_leading_anchor("^" <> rest), do: strip_leading_anchor(rest)
  defp strip_leading_anchor(value), do: value

  defp strip_trailing_anchor(""), do: ""

  defp strip_trailing_anchor(value) do
    if String.ends_with?(value, "$") do
      value
      |> String.trim_trailing("$")
      |> strip_trailing_anchor()
    else
      value
    end
  end

  defp delete_first([], _value), do: []
  defp delete_first([value | rest], value), do: rest
  defp delete_first([head | rest], value), do: [head | delete_first(rest, value)]
end

