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
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator

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
    resolved_entries =
      series
      |> MetricSeriesEvaluator.resolve_category_rows(widget, 1)
      |> MetricSeriesEvaluator.category_entries()

    if resolved_entries == [] do
      nil
    else
      limit = widget_limit(widget)
      sort = widget_sort(widget)
      empty_message = widget_empty_message(widget)

      items =
        resolved_entries
        |> Enum.reject(&zero_entry?/1)
        |> sort_items(sort)
        |> maybe_limit(limit)
        |> Enum.map(fn %{name: full_path, value: value, color: color, source_path: source_path} ->
          %{
            path: source_path || full_path,
            label: display_label(full_path, widget),
            value: value,
            formatted_value: format_value(value),
            color: color
          }
        end)

      dataset = %{
        id: widget_id(widget),
        path: primary_entry_path(resolved_entries),
        total_nodes: length(resolved_entries),
        limit: limit,
        items: items,
        empty_message: empty_message
      }

      if items == [] do
        Logger.debug(fn ->
          "[ListWidget #{widget_id(widget)}] no values for resolved entries=#{inspect(resolved_entries, limit: 10)}"
        end)
      end

      dataset
    end
  rescue
    error ->
      Logger.debug(fn ->
        "[ListWidget #{widget_id(widget)}] failed to build dataset reason=#{inspect(error)}"
      end)

      nil
  end

  defp list_widget?(%{"type" => type}), do: String.downcase(to_string(type)) == "list"
  defp list_widget?(%{type: type}), do: String.downcase(to_string(type)) == "list"
  defp list_widget?(_), do: false

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

  defp sort_items(items, "asc"), do: Enum.sort_by(items, & &1.value, :asc)
  defp sort_items(items, "alpha"), do: Enum.sort_by(items, & &1.name, :asc)
  defp sort_items(items, "alpha_desc"), do: Enum.sort_by(items, & &1.name, :desc)
  defp sort_items(items, _), do: Enum.sort_by(items, & &1.value, :desc)

  defp zero_entry?(%{value: value}) when is_number(value), do: value == 0
  defp zero_entry?(%{value: value}) when is_nil(value), do: true
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

  defp primary_entry_path([%{source_path: source_path} | _]), do: source_path
  defp primary_entry_path(_), do: nil

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
