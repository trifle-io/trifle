defmodule TrifleApp.Components.DashboardWidgets.Table do
  @moduledoc false

  alias Trifle.Stats.Series
  alias Trifle.Stats.Tabler
  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.Components.DashboardWidgets.MetricSeries
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEvaluator
  require Logger

  @spec datasets(Series.t() | nil, list()) :: list()
  def datasets(nil, _grid_items), do: []

  def datasets(%Series{} = series_struct, grid_items) do
    grid_items
    |> Enum.filter(&table_widget?/1)
    |> Enum.map(&build_dataset(series_struct, &1))
    |> Enum.reject(&is_nil/1)
  end

  @spec dataset(Series.t() | nil, map()) :: map() | nil
  def dataset(nil, _widget), do: nil
  def dataset(%Series{} = series_struct, widget), do: build_dataset(series_struct, widget)

  defp table_widget?(%{"type" => type}), do: String.downcase(to_string(type)) == "table"
  defp table_widget?(%{type: type}), do: String.downcase(to_string(type)) == "table"
  defp table_widget?(_), do: false

  defp build_dataset(series_struct, widget) do
    table_stats = tabulate_series(series_struct)
    resolved_rows = MetricSeriesEvaluator.resolve_timeline_rows(series_struct, widget)
    visible_rows = MetricSeriesEvaluator.visible_rows(resolved_rows)

    if visible_rows == [] do
      log_debug(widget, "table widget has no visible series")
      nil
    else
      columns =
        series_struct
        |> series_at()
        |> Enum.map(&normalize_timestamp_key/1)
        |> Enum.reverse()
        |> Enum.with_index(1)
        |> Enum.map(fn {at, index} -> %{at: at, index: index} end)

      {rows, values, color_paths} =
        Enum.reduce(visible_rows, {[], %{}, []}, fn resolved, {row_acc, value_acc, color_acc} ->
          visible_entries =
            case MetricSeries.row_kind(resolved.row) do
              "path" -> table_path_entries(table_stats, resolved.row)
              _ -> expression_table_entries(resolved)
            end

          visible_entries
          |> Enum.with_index()
          |> Enum.reduce({row_acc, value_acc, color_acc}, fn {{_binding_key, entry}, emitted_index},
                                                             {inner_rows, inner_values, inner_colors} ->
            path_key =
              entry.source_path ||
                "__table__.#{resolved.index}.#{emitted_index}.#{String.replace(entry.name, ".", "__")}"

            display_path = table_display_path(resolved.row, entry)
            color = Helpers.resolve_series_color(MetricSeries.row_color_selector(resolved.row), emitted_index)

            row = %{
              path: path_key,
              display_path: display_path,
              index: length(inner_rows) + 1,
              color: color,
              path_html: colored_path_html(display_path, color)
            }

            updated_values =
              entry.samples
              |> Enum.reduce(inner_values, fn {at, value}, acc ->
                Map.put(acc, {path_key, normalize_timestamp_key(at)}, value)
              end)

            {inner_rows ++ [row], updated_values, inner_colors ++ [display_path]}
          end)
        end)

      log_debug(widget, "table dataset prepared", rows: length(rows), columns: length(columns))

      %{
        id: widget_id(widget),
        rows: rows,
        columns: columns,
        values: values,
        color_paths: color_paths,
        granularity: series_granularity(series_struct),
        empty_message: "No values available for the selected timeframe.",
        mode: "aggrid"
      }
    end
  end

  defp table_display_path(row, entry) do
    case MetricSeries.row_kind(row) do
      "path" ->
        trim_display_path(entry.source_path || entry.name, [MetricSeries.row_path(row)])

      _ ->
        entry.name
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

  defp table_path_entries(nil, _row), do: []

  defp table_path_entries(table_stats, row) do
    filter = MetricSeries.row_path(row)
    paths = Map.get(table_stats, :paths, [])

    paths
    |> Enum.filter(&match_path?(to_string(&1), filter))
    |> Enum.sort()
    |> Enum.map(fn path ->
      path_key = to_string(path)

      {path_key,
       %{
         name: trim_display_path(path_key, [filter]),
         source_path: path_key,
         samples: samples_for_table_path(table_stats, path_key)
       }}
    end)
  end

  defp expression_table_entries(resolved) do
    resolved.entries
    |> Enum.sort_by(fn {_binding_key, entry} -> entry.name end)
  end

  defp samples_for_table_path(table_stats, path_key) do
    table_stats
    |> Map.get(:values, %{})
    |> Enum.reduce(%{}, fn
      {{^path_key, at}, value}, acc -> Map.put(acc, at, value)
      _, acc -> acc
    end)
  end

  defp match_path?(_path, ""), do: false
  defp match_path?(_path, "*"), do: true

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

  defp colored_path_html(path, color) do
    with safe_color when is_binary(safe_color) <- normalize_hex_color(color),
         safe_path when safe_path != "" <- path |> to_string() |> String.trim() do
      safe_path
      |> String.split(".")
      |> Enum.map(fn segment ->
        escaped_segment =
          segment
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.safe_to_string()

        "<span style=\"color: #{safe_color} !important\">#{escaped_segment}</span>"
      end)
      |> Enum.join(".")
    else
      _ -> nil
    end
  end

  defp normalize_hex_color(color) when is_binary(color) do
    trimmed = String.trim(color)

    cond do
      Regex.match?(~r/^#([0-9a-fA-F]{6})$/, trimmed) ->
        trimmed

      true ->
        case Regex.run(~r/^#([0-9a-fA-F]{3})$/, trimmed) do
          [_, short_hex] ->
            expanded =
              short_hex
              |> String.graphemes()
              |> Enum.map_join(fn nibble -> nibble <> nibble end)

            "#" <> expanded

          _ ->
            nil
        end
    end
  end

  defp normalize_hex_color(_), do: nil

  defp series_at(%Series{series: series_map}) when is_map(series_map) do
    Map.get(series_map, :at) || Map.get(series_map, "at") || []
  end

  defp series_at(_), do: []

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

  defp normalize_timestamp_key(%DateTime{} = datetime) do
    DateTime.shift_zone!(datetime, "Etc/UTC")
  end

  defp normalize_timestamp_key(%NaiveDateTime{} = datetime) do
    DateTime.from_naive!(datetime, "Etc/UTC")
  end

  defp normalize_timestamp_key(other), do: other

  defp widget_id(%{"id" => id}), do: to_string(id)
  defp widget_id(%{id: id}), do: to_string(id)
  defp widget_id(_), do: nil

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
