defmodule TrifleApp.Components.DashboardWidgets.SeriesOrder do
  @moduledoc false

  @default_mode "natural"
  @priority_fallback_rank 1_000_000

  def normalize_mode(value, default \\ @default_mode)

  def normalize_mode(value, default) when is_binary(default) do
    normalized_default =
      default
      |> to_string()
      |> String.trim()
      |> String.downcase()
      |> case do
        "alpha" -> "alpha"
        _ -> @default_mode
      end

    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "alpha" -> "alpha"
      "natural" -> "natural"
      _ -> normalized_default
    end
  end

  def normalize_mode(_value, default), do: normalize_mode(default, @default_mode)

  def normalize_priority(value)

  def normalize_priority(value) when is_list(value) do
    value
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def normalize_priority(value) when is_binary(value) do
    value
    |> String.split(~r/[\n,]+/, trim: true)
    |> normalize_priority()
  end

  def normalize_priority(nil), do: []
  def normalize_priority(value), do: value |> to_string() |> normalize_priority()

  def priority_text(widget_or_value) do
    widget_or_value
    |> priority_list()
    |> Enum.join("\n")
  end

  def priority_last_text(widget_or_value) do
    widget_or_value
    |> priority_last_list()
    |> Enum.join("\n")
  end

  def priority_list(widget_or_value) when is_map(widget_or_value) do
    widget_or_value
    |> Map.get("series_priority", Map.get(widget_or_value, :series_priority, []))
    |> normalize_priority()
  end

  def priority_list(widget_or_value), do: normalize_priority(widget_or_value)

  def priority_last_list(widget_or_value) when is_map(widget_or_value) do
    widget_or_value
    |> Map.get("series_priority_last", Map.get(widget_or_value, :series_priority_last, []))
    |> normalize_priority()
  end

  def priority_last_list(_widget_or_value), do: []

  def priority_rows(widget_or_value) do
    widget_or_value
    |> priority_list()
    |> Enum.with_index()
    |> Enum.map(fn {value, index} -> %{"index" => index, "value" => value} end)
    |> append_blank_row()
  end

  def priority_visual_rows(widget_or_value) do
    {first_rows, next_index} =
      widget_or_value
      |> priority_list()
      |> priority_group_rows(0, "first")

    {last_rows, _next_index} =
      widget_or_value
      |> priority_last_list()
      |> priority_group_rows(next_index, "last")

    %{first: first_rows, last: last_rows}
  end

  def visual_params_present?(params) when is_map(params) do
    Map.has_key?(params, "series_priority_item") or Map.has_key?(params, "series_priority_item[]")
  end

  def visual_params_present?(_params), do: false

  def normalize_priority_rows(value) when is_map(value) do
    value
    |> Enum.sort_by(fn {index, _value} -> index_sort_key(index) end)
    |> Enum.map(fn {_index, item} -> item end)
    |> normalize_priority()
  end

  def normalize_priority_rows(value), do: normalize_priority(value)

  def normalize_priority_rows(items, groups, target_group) do
    item_values = indexed_values(items)
    group_values = indexed_values(groups)
    normalized_target = normalize_group(target_group)

    item_values
    |> Enum.sort_by(fn {index, _value} -> index_sort_key(index) end)
    |> Enum.filter(fn {index, _value} ->
      group_values
      |> Map.get(index, "first")
      |> normalize_group()
      |> Kernel.==(normalized_target)
    end)
    |> Enum.map(fn {_index, item} -> item end)
    |> normalize_priority()
  end

  def sort_named_items(items, widget, opts \\ [])

  def sort_named_items(items, widget, opts) when is_list(items) do
    config = sort_config(widget, opts)
    name_fun = Keyword.get(opts, :name_fun, &default_name/1)

    Enum.sort_by(items, fn item ->
      sort_key(name_fun.(item), config)
    end)
  end

  def sort_named_items(items, _widget, _opts), do: items

  def sort_entry_pairs(entries, widget, opts \\ [])

  def sort_entry_pairs(entries, widget, opts) when is_map(entries) do
    entries
    |> Map.to_list()
    |> sort_entry_pairs(widget, opts)
  end

  def sort_entry_pairs(entries, widget, opts) when is_list(entries) do
    config = sort_config(widget, opts)

    Enum.sort_by(entries, fn {_binding_key, entry} ->
      name =
        Map.get(entry, :name) ||
          Map.get(entry, "name") ||
          ""

      sort_key(name, config)
    end)
  end

  def sort_entry_pairs(entries, _widget, _opts), do: entries

  defp sort_config(widget, opts) do
    default_mode = Keyword.get(opts, :default_mode, @default_mode)

    %{
      mode: series_sort(widget, default_mode),
      priority: priority_list(widget),
      priority_last: priority_last_list(widget)
    }
  end

  defp series_sort(widget, default_mode) when is_map(widget) do
    widget
    |> Map.get("series_sort", Map.get(widget, :series_sort, default_mode))
    |> normalize_mode(default_mode)
  end

  defp series_sort(_widget, default_mode), do: normalize_mode(default_mode, @default_mode)

  defp sort_key(name, %{mode: "alpha", priority: priority, priority_last: priority_last}) do
    normalized = normalize_name(name)

    case priority_position(normalized, priority, priority_last) do
      {:first, rank} -> {0, rank, normalized, natural_sort_key(normalized)}
      {:last, rank} -> {2, rank, normalized, natural_sort_key(normalized)}
      :middle -> {1, @priority_fallback_rank, normalized, natural_sort_key(normalized)}
    end
  end

  defp sort_key(name, %{priority: priority, priority_last: priority_last}) do
    normalized = normalize_name(name)

    case priority_position(normalized, priority, priority_last) do
      {:first, rank} -> {0, rank, natural_sort_key(normalized), normalized}
      {:last, rank} -> {2, rank, natural_sort_key(normalized), normalized}
      :middle -> {1, @priority_fallback_rank, natural_sort_key(normalized), normalized}
    end
  end

  defp priority_position(name, priority, priority_last) do
    case priority_index(name, priority) do
      first_rank when is_integer(first_rank) ->
        {:first, first_rank}

      nil ->
        case priority_index(name, priority_last) do
          last_rank when is_integer(last_rank) -> {:last, last_rank}
          nil -> :middle
        end
    end
  end

  defp priority_index(name, priority) when is_binary(name) and is_list(priority) do
    leaf = leaf_name(name)

    Enum.find_index(priority, fn candidate ->
      normalized_candidate = normalize_name(candidate)
      normalized_candidate == name or normalized_candidate == leaf
    end)
  end

  defp priority_index(_name, _priority), do: nil

  defp priority_group_rows(values, start_index, group) do
    rows =
      values
      |> Enum.with_index(start_index)
      |> Enum.map(fn {value, index} ->
        %{"index" => index, "value" => value, "group" => group}
      end)

    blank_index = start_index + length(rows)
    {rows ++ [%{"index" => blank_index, "value" => "", "group" => group}], blank_index + 1}
  end

  defp normalize_name(value), do: value |> to_string() |> String.trim()

  defp leaf_name(name) do
    name
    |> String.split(".")
    |> List.last()
    |> case do
      nil -> name
      value -> value
    end
  end

  defp default_name(item) when is_map(item) do
    Map.get(item, :name) || Map.get(item, "name") || ""
  end

  defp default_name(item), do: to_string(item)

  defp append_blank_row(rows) do
    rows ++ [%{"index" => length(rows), "value" => ""}]
  end

  defp index_sort_key(index) do
    case Integer.parse(to_string(index)) do
      {parsed, ""} -> {0, parsed}
      _ -> {1, to_string(index)}
    end
  end

  defp natural_sort_key(nil), do: [{:str, ""}]

  defp natural_sort_key(name) when is_binary(name) do
    case Regex.scan(~r/\d+|\D+/, name) do
      [] ->
        [{:str, String.downcase(name)}]

      segments ->
        segments
        |> Enum.map(&List.first/1)
        |> Enum.map(&natural_token/1)
    end
  end

  defp natural_sort_key(other), do: other |> to_string() |> natural_sort_key()

  defp natural_token(segment) do
    cond do
      segment == "" ->
        {:str, ""}

      true ->
        case Integer.parse(segment) do
          {int, ""} ->
            {:num, int}

          _ ->
            case Float.parse(segment) do
              {float, ""} -> {:num, float}
              _ -> {:str, String.downcase(segment)}
            end
        end
    end
  end

  defp indexed_values(value) when is_map(value) do
    Map.new(value, fn {index, field_value} -> {to_string(index), field_value} end)
  end

  defp indexed_values(value) when is_list(value) do
    value
    |> Enum.with_index()
    |> Map.new(fn {field_value, index} -> {Integer.to_string(index), field_value} end)
  end

  defp indexed_values(nil), do: %{}
  defp indexed_values(value), do: %{"0" => value}

  defp normalize_group(value) do
    case value |> to_string() |> String.trim() |> String.downcase() do
      "last" -> "last"
      _ -> "first"
    end
  end
end
