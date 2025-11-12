defmodule TrifleApp.Components.DashboardWidgets.Table do
  @moduledoc false

  alias Trifle.Stats.Series
  alias Trifle.Stats.Tabler
  alias TrifleApp.Components.DataTable
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: DashboardWidgetHelpers
  require Logger

  @spec datasets(Series.t() | nil, list()) :: list()
  def datasets(nil, _grid_items), do: []

  def datasets(%Series{} = series_struct, grid_items) do
    table_stats = tabulate_series(series_struct)

    grid_items
    |> Enum.filter(&table_widget?/1)
    |> Enum.map(&build_dataset(series_struct, table_stats, &1))
    |> Enum.reject(&is_nil/1)
  end

  @spec dataset(Series.t() | nil, map()) :: map() | nil
  def dataset(nil, _widget), do: nil

  def dataset(%Series{} = series_struct, widget) do
    table_stats = tabulate_series(series_struct)
    build_dataset(series_struct, table_stats, widget)
  end

  defp table_widget?(%{"type" => type}), do: String.downcase(to_string(type)) == "table"
  defp table_widget?(%{type: type}), do: String.downcase(to_string(type)) == "table"
  defp table_widget?(_), do: false

  defp build_dataset(series_struct, table_stats, widget) do
    filters = widget_paths(widget)

    if filters == [] do
      log_debug(widget, "table widget has no configured paths")
      nil
    else
      normalized_stats = ensure_table_stats(table_stats, series_struct)

      paths = normalized_stats[:paths] || []
      matching_paths = filter_paths(paths, filters)

      display_overrides =
        matching_paths
        |> Enum.map(fn path ->
          {path, trim_display_path(path, filters)}
        end)
        |> Enum.into(%{})

      empty_message =
        if matching_paths == [] do
          "No data available yet."
        else
          "No values available for the selected timeframe."
        end

      table_dataset =
        DataTable.from_stats(
          normalized_stats,
          paths: matching_paths,
          display_paths: display_overrides,
          granularity: series_granularity(series_struct),
          reverse_columns: true,
          empty_message: empty_message,
          id: widget_id(widget)
        )

      log_debug(widget, "table dataset prepared",
        filters: filters,
        matching_paths: length(matching_paths)
      )

      table_mode =
        widget
        |> Map.get("table_mode", "html")
        |> DashboardWidgetHelpers.normalize_table_mode()

      table_dataset
      |> Map.put(:id, widget_id(widget))
      |> Map.put(:mode, table_mode)
    end
  end

  defp tabulate_series(%Series{series: series_map}) when is_map(series_map) do
    try do
      Tabler.tabulize(series_map)
    rescue
      _ -> nil
    end
  end

  defp tabulate_series(_), do: nil

  defp widget_paths(widget) do
    raw_value =
      Map.get(widget, "paths") ||
        Map.get(widget, :paths) ||
        case widget do
          %{"paths" => value} -> value
          %{paths: value} -> value
          _ -> nil
        end

    raw_paths =
      cond do
        is_list(raw_value) ->
          raw_value

        not is_nil(raw_value) ->
          [raw_value]

        true ->
          case fetch_single_path(widget) do
            nil -> []
            value -> [value]
          end
      end

    raw_paths
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp filter_paths(paths, filters) do
    Enum.filter(paths, fn path ->
      Enum.any?(filters, &match_path?(to_string(path), &1))
    end)
  end

  defp match_path?(_path, ""), do: false
  defp match_path?(path, "*"), do: true

  defp match_path?(path, filter) do
    cond do
      String.ends_with?(filter, ".*") ->
        base = String.trim_trailing(filter, ".*")
        path == base || String.starts_with?(path, base <> ".")

      String.contains?(filter, "*") ->
        wildcard = Regex.escape(filter) |> String.replace("\\*", ".*")
        Regex.match?(Regex.compile!("^#{wildcard}$"), path)

      true ->
        path == filter || String.starts_with?(path, filter <> ".")
    end
  end

  defp trim_display_path(path, filters) do
    normalized_path = to_string(path)

    best_prefix =
      filters
      |> Enum.map(&String.trim_trailing(&1, ".*"))
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.filter(fn prefix ->
        normalized_path == prefix || String.starts_with?(normalized_path, prefix <> ".")
      end)
      |> Enum.max_by(&String.length/1, fn -> nil end)

    cond do
      is_nil(best_prefix) ->
        normalized_path

      normalized_path == best_prefix ->
        normalized_path
        |> String.split(".")
        |> List.last()
        |> Kernel.||(normalized_path)

      true ->
        String.replace_prefix(normalized_path, best_prefix <> ".", "")
    end
  end

  defp series_granularity(%Series{series: series_map}) when is_map(series_map) do
    Map.get(series_map, :granularity) ||
      Map.get(series_map, "granularity") ||
      series_map
      |> Map.get(:meta, %{})
      |> Map.get(:granularity) ||
      series_map
      |> Map.get("meta", %{})
      |> Map.get("granularity")
  end

  defp series_granularity(_), do: nil

  defp widget_id(%{"id" => id}), do: to_string(id)
  defp widget_id(%{id: id}), do: to_string(id)
  defp widget_id(_), do: nil

  defp ensure_table_stats(nil, series_struct) do
    %{
      at: fallback_at(series_struct),
      paths: [],
      values: %{}
    }
  end

  defp ensure_table_stats(table_stats, series_struct) when is_map(table_stats) do
    table_stats
    |> Map.put_new(:paths, [])
    |> Map.put_new(:values, %{})
    |> ensure_at(series_struct)
  end

  defp ensure_table_stats(_other, series_struct), do: ensure_table_stats(nil, series_struct)

  defp ensure_at(stats, series_struct) do
    case Map.get(stats, :at) do
      list when is_list(list) and list != [] ->
        stats

      _ ->
        Map.put(stats, :at, fallback_at(series_struct))
    end
  end

  defp fallback_at(%Series{series: series_map}) when is_map(series_map) do
    cond do
      is_list(series_map[:at]) and series_map[:at] != [] -> series_map[:at]
      is_list(series_map["at"]) and series_map["at"] != [] -> series_map["at"]
      true -> []
    end
  end

  defp fallback_at(_), do: []

  defp fetch_single_path(widget) do
    Map.get(widget, "path") ||
      Map.get(widget, :path) ||
      case widget do
        %{"path" => value} -> value
        %{path: value} -> value
        _ -> nil
      end
  end

  defp log_debug(widget, message, metadata \\ []) do
    widget_id = widget_id(widget) || "unknown"

    Logger.debug(fn ->
      meta =
        metadata
        |> Enum.map(fn {key, value} -> "#{key}=#{inspect(value)}" end)
        |> Enum.join(" ")

      "[TableWidget #{widget_id}] #{message}" <>
        if(meta == "", do: "", else: " (#{meta})")
    end)
  end
end
