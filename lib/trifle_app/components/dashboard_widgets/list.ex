defmodule TrifleApp.Components.DashboardWidgets.List do
  @moduledoc """
  Dataset builder for list widgets.

  List widgets display a ranked list of categorical values resolved from a
  configurable stats path (e.g., `keys` or `metrics.*`). Values are aggregated
  across the selected timeframe and rendered with consistent chart colors.
  """

  require Logger

  alias Decimal
  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers

  @spec datasets(Series.t() | nil, list()) :: list()
  def datasets(nil, _grid_items), do: []

  def datasets(%Series{} = series, grid_items) do
    grid_items
    |> Enum.filter(&list_widget?/1)
    |> Enum.map(&dataset(series, &1))
    |> Enum.reject(&is_nil/1)
  end

  @spec dataset(Series.t() | nil, map()) :: map() | nil
  def dataset(nil, _widget), do: nil

  def dataset(%Series{} = series, widget) do
    path = widget_path(widget)

    if is_nil(path) do
      nil
    else
      limit = widget_limit(widget)
      sort = widget_sort(widget)
      empty_message = widget_empty_message(widget)
      raw_category = Series.format_category(series, path, 1)

      normalized_entries = normalize_category_entries(raw_category)

      selectors =
        widget
        |> Map.get("series_color_selectors", %{})
        |> WidgetHelpers.normalize_series_color_selectors_map()

      selector = WidgetHelpers.selector_for_path(selectors, path)
      parsed_selector = WidgetHelpers.parse_series_color_selector(selector)

      items =
        normalized_entries
        |> Enum.reject(&zero_entry?/1)
        |> sort_items(sort)
        |> maybe_limit(limit)
        |> Enum.with_index()
        |> Enum.map(fn {{full_path, value}, index} ->
          color =
            case parsed_selector do
              %{type: :palette_rotate} -> WidgetHelpers.resolve_series_color(selector, index)
              _ -> WidgetHelpers.resolve_series_color(selector, 0)
            end

          %{
            path: full_path,
            label: display_label(full_path, widget),
            value: value,
            formatted_value: format_value(value),
            color: color
          }
        end)

      dataset = %{
        id: widget_id(widget),
        path: path,
        total_nodes: length(normalized_entries),
        limit: limit,
        items: items,
        empty_message: empty_message
      }

      if items == [] do
        Logger.debug(fn ->
          "[ListWidget #{widget_id(widget)}] no values for path=#{path}. raw=#{inspect(raw_category, limit: 10)} normalized=#{inspect(normalized_entries, limit: 10)}"
        end)
      end

      dataset
    end
  rescue
    error ->
      Logger.debug(fn ->
        "[ListWidget #{widget_id(widget)}] failed to build dataset for path=#{widget_path(widget)} reason=#{inspect(error)}"
      end)

      nil
  end

  defp list_widget?(%{"type" => type}), do: String.downcase(to_string(type)) == "list"
  defp list_widget?(%{type: type}), do: String.downcase(to_string(type)) == "list"
  defp list_widget?(_), do: false

  defp widget_path(widget) do
    widget["path"] || widget[:path] || first_path(widget)
  end

  defp first_path(widget) do
    cond do
      is_list(widget["paths"]) -> List.first(widget["paths"])
      is_list(widget[:paths]) -> List.first(widget[:paths])
      true -> nil
    end
  end

  defp widget_limit(widget) do
    widget
    |> Map.get("limit") ||
      Map.get(widget, :limit)
      |> normalize_limit()
  end

  defp widget_sort(widget) do
    widget
    |> Map.get("sort") || Map.get(widget, :sort) ||
      "desc"
      |> to_string()
      |> String.downcase()
  end

  defp widget_empty_message(widget) do
    widget
    |> Map.get("empty_message") || Map.get(widget, :empty_message) ||
      "No data available yet."
  end

  defp normalize_category_entries(map) when is_map(map) do
    map
    |> flatten_category_entries()
  end

  defp normalize_category_entries(list) when is_list(list) do
    list
    |> Enum.flat_map(&normalize_category_entry/1)
  end

  defp normalize_category_entries(_), do: []

  defp normalize_category_entry({path, value}),
    do: [{to_string(path), to_float(value)}]

  defp normalize_category_entry(%{path: path, value: value}) do
    [{to_string(path), to_float(value)}]
  rescue
    _ -> []
  end

  defp normalize_category_entry(%{} = map) do
    map
    |> flatten_category_entries()
    |> Enum.map(fn {path, value} -> {to_string(path), to_float(value)} end)
  rescue
    _ -> []
  end

  defp normalize_category_entry(_), do: []

  defp flatten_category_entries(map, prefix \\ nil)

  defp flatten_category_entries(map, prefix) when is_map(map) do
    map
    |> Enum.flat_map(fn {key, value} ->
      key_str = key |> to_string() |> String.trim()
      full_key = if prefix && prefix != "", do: prefix <> "." <> key_str, else: key_str

      cond do
        is_map(value) ->
          flatten_category_entries(value, full_key)

        is_number(value) ->
          [{to_string(full_key), to_float(value)}]

        match?(%Decimal{}, value) ->
          [{to_string(full_key), to_float(value)}]

        true ->
          []
      end
    end)
  end

  defp flatten_category_entries(_other, _prefix), do: []

  defp sort_items(items, "asc"), do: Enum.sort_by(items, fn {_k, v} -> v end, :asc)
  defp sort_items(items, "alpha"), do: Enum.sort_by(items, fn {k, _v} -> k end, :asc)
  defp sort_items(items, "alpha_desc"), do: Enum.sort_by(items, fn {k, _v} -> k end, :desc)
  defp sort_items(items, _), do: Enum.sort_by(items, fn {_k, v} -> v end, :desc)

  defp zero_entry?({_, value}) when is_number(value), do: value == 0
  defp zero_entry?({_, value}) when is_nil(value), do: true
  defp zero_entry?(_), do: true

  defp display_label(path, widget) do
    case Map.get(widget, "label_strategy") || Map.get(widget, :label_strategy) do
      "full_path" -> path
      _ -> List.last(String.split(path, ".")) || path
    end
  end

  defp format_value(value) when is_number(value) do
    cond do
      value >= 1_000_000_000 -> suffix(value / 1_000_000_000, "b")
      value >= 1_000_000 -> suffix(value / 1_000_000, "m")
      value >= 1_000 -> suffix(value / 1_000, "k")
      true -> format_number(value)
    end
  end

  defp format_value(_), do: "0"

  defp suffix(value, label) do
    cond do
      value >= 100 -> "#{format_number(Float.round(value, 0))}#{label}"
      value >= 10 -> "#{format_number(Float.round(value, 1))}#{label}"
      true -> "#{format_number(Float.round(value, 2))}#{label}"
    end
  end

  defp format_number(number) when is_integer(number), do: Integer.to_string(number)

  defp format_number(number) when is_float(number),
    do: strip_trailing_zeros(:erlang.float_to_binary(number, decimals: 2))

  defp format_number(number), do: to_string(number)

  defp strip_trailing_zeros(value) do
    value
    |> String.replace(~r/\.00$/, "")
    |> String.replace(~r/(\.\d*[1-9])0+$/, "\\1")
  end

  defp widget_id(%{"id" => id}), do: to_string(id)
  defp widget_id(%{id: id}), do: to_string(id)
  defp widget_id(_), do: nil

  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_number(value), do: value * 1.0
  defp to_float(_), do: 0.0

  defp normalize_limit(value) do
    cond do
      value in [nil, ""] ->
        nil

      is_integer(value) and value > 0 ->
        value

      is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp maybe_limit(items, nil), do: items
  defp maybe_limit(items, limit) when is_integer(limit) and limit > 0, do: Enum.take(items, limit)
  defp maybe_limit(items, _), do: items
end
