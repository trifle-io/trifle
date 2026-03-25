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

  def priority_list(widget_or_value) when is_map(widget_or_value) do
    widget_or_value
    |> Map.get("series_priority", Map.get(widget_or_value, :series_priority, []))
    |> normalize_priority()
  end

  def priority_list(widget_or_value), do: normalize_priority(widget_or_value)

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
      priority: priority_list(widget)
    }
  end

  defp series_sort(widget, default_mode) when is_map(widget) do
    widget
    |> Map.get("series_sort", Map.get(widget, :series_sort, default_mode))
    |> normalize_mode(default_mode)
  end

  defp series_sort(_widget, default_mode), do: normalize_mode(default_mode, @default_mode)

  defp sort_key(name, %{mode: "alpha", priority: priority}) do
    normalized = normalize_name(name)
    {priority_rank(normalized, priority), normalized, natural_sort_key(normalized)}
  end

  defp sort_key(name, %{priority: priority}) do
    normalized = normalize_name(name)
    {priority_rank(normalized, priority), natural_sort_key(normalized), normalized}
  end

  defp priority_rank(name, priority) when is_binary(name) and is_list(priority) do
    leaf = leaf_name(name)

    Enum.find_index(priority, fn candidate ->
      normalized_candidate = normalize_name(candidate)
      normalized_candidate == name or normalized_candidate == leaf
    end) || @priority_fallback_rank
  end

  defp priority_rank(_name, _priority), do: @priority_fallback_rank

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
end
