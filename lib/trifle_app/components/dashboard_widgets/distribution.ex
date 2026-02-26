defmodule TrifleApp.Components.DashboardWidgets.Distribution do
  @moduledoc false

  alias Trifle.Stats.Series
  alias Trifle.Stats.Designator.{Custom, Geometric, Linear}
  alias TrifleApp.Components.DashboardWidgets.Helpers, as: WidgetHelpers
  alias TrifleApp.Components.DashboardWidgets.SharedParse
  require Logger

  @type dataset :: %{
          id: String.t(),
          widget_type: String.t(),
          mode: String.t(),
          chart_type: String.t(),
          path_aggregation: String.t(),
          color_mode: String.t() | nil,
          color_config: map() | nil,
          legend: boolean(),
          bucket_labels: list(String.t()),
          vertical_bucket_labels: list(String.t()) | nil,
          series: list(),
          designator: map(),
          designators: map(),
          points?: boolean(),
          errors: list(String.t())
        }

  @spec datasets(Series.t() | nil, list()) :: list()
  def datasets(nil, _grid_items), do: []

  def datasets(series_struct, grid_items) do
    items =
      grid_items
      |> Enum.filter(fn item ->
        item_type = String.downcase(to_string(item["type"] || item["widget_type"] || ""))
        item_type in ["distribution", "heatmap"]
      end)
      |> Enum.map(&dataset(series_struct, &1))
      |> Enum.reject(&is_nil/1)

    Logger.debug(fn ->
      summary =
        Enum.map(items, fn i ->
          %{
            id: i.id,
            buckets: length(i.bucket_labels || []),
            series:
              Enum.map(i.series || [], fn s ->
                values =
                  Map.get(s, :values) || Map.get(s, "values") || Map.get(s, :points) ||
                    Map.get(s, "points") || []

                %{name: s.name, buckets: length(values)}
              end),
            errors: i.errors || []
          }
        end)

      "Distribution widgets: " <> inspect(summary)
    end)

    items
  end

  @spec dataset(Series.t() | nil, map()) :: dataset() | nil
  def dataset(nil, _item), do: nil

  def dataset(series_struct, item) do
    id = to_string(item["id"])

    widget_type =
      item
      |> Map.get("widget_type", Map.get(item, "type", "distribution"))
      |> normalize_widget_type()

    paths = normalized_paths(item)
    default_mode = if widget_type == "heatmap", do: "3d", else: "2d"

    mode =
      item
      |> Map.get("mode", default_mode)
      |> normalize_mode()
      |> case do
        "2d" when widget_type == "heatmap" -> "3d"
        value -> value
      end

    default_chart_type = if widget_type == "heatmap", do: "heatmap", else: "bar"

    chart_type =
      item
      |> Map.get("chart_type", default_chart_type)
      |> normalize_chart_type(default_chart_type)
      |> case do
        _ when widget_type == "heatmap" -> "heatmap"
        value -> value
      end

    legend = !!item["legend"]

    path_inputs =
      item
      |> WidgetHelpers.path_inputs_for_form("distribution")
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)

    selectors =
      item
      |> Map.get("series_color_selectors", %{})
      |> WidgetHelpers.normalize_series_color_selectors_map()

    path_color_map =
      paths
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {path, index}, acc ->
        path_input =
          path_inputs
          |> Enum.at(index)
          |> case do
            nil -> path
            "" -> path
            value -> value
          end

        selector = WidgetHelpers.selector_for_path(selectors, path_input)
        color = WidgetHelpers.resolve_series_color(selector, index)
        Map.put(acc, path, color)
      end)

    path_aggregation =
      item
      |> Map.get("path_aggregation")
      |> WidgetHelpers.normalize_distribution_path_aggregation()

    fallback_heatmap_color = fallback_heatmap_color(paths, path_color_map)

    color_mode =
      case widget_type do
        "heatmap" ->
          item
          |> Map.get("color_mode")
          |> WidgetHelpers.normalize_heatmap_color_mode()

        _ ->
          nil
      end

    color_config =
      case widget_type do
        "heatmap" ->
          item
          |> Map.get("color_config", %{})
          |> WidgetHelpers.normalize_heatmap_color_config(fallback_heatmap_color)

        _ ->
          nil
      end

    if paths == [] do
      %{
        id: id,
        widget_type: widget_type,
        mode: mode,
        chart_type: chart_type,
        path_aggregation: path_aggregation,
        color_mode: color_mode,
        color_config: color_config,
        legend: legend,
        bucket_labels: [],
        vertical_bucket_labels: nil,
        series: [],
        designator: %{},
        designators: %{},
        points?: mode == "3d",
        errors: ["No metric paths configured"]
      }
    else
      designators_config = WidgetHelpers.normalize_distribution_designators(%{}, item)
      %{descriptors: descriptors, errors: raw_errors} = build_designators(designators_config)
      designators_summary = summarize_designators(descriptors)

      horizontal_descriptor =
        descriptors
        |> Map.get("horizontal")
        |> Kernel.||(Map.get(descriptors, :horizontal))

      designator_errors = designator_error_messages(raw_errors, mode)

      cond do
        is_nil(horizontal_descriptor) ->
          %{
            id: id,
            widget_type: widget_type,
            mode: mode,
            chart_type: chart_type,
            path_aggregation: path_aggregation,
            color_mode: color_mode,
            color_config: color_config,
            legend: legend,
            bucket_labels: [],
            vertical_bucket_labels:
              Map.get(Map.get(designators_summary, "vertical", %{}), :bucket_labels),
            series: [],
            designator: %{},
            designators: designators_summary,
            points?: mode == "3d",
            errors:
              if(designator_errors == [],
                do: ["Horizontal designator is required"],
                else: designator_errors
              )
          }

        true ->
          series =
            case {mode, Map.get(descriptors, "vertical")} do
              {"3d", %{} = vertical_descriptor} ->
                series_for_paths_3d(
                  series_struct,
                  paths,
                  horizontal_descriptor,
                  vertical_descriptor,
                  item,
                  path_color_map
                )

              _ ->
                series_for_paths(
                  series_struct,
                  paths,
                  horizontal_descriptor,
                  item,
                  path_color_map
                )
            end

          series =
            case mode do
              "3d" -> ensure_points_for_3d(series, horizontal_descriptor.bucket_labels)
              _ -> series
            end

          series =
            maybe_aggregate_path_series(
              series,
              mode,
              path_aggregation,
              horizontal_descriptor.bucket_labels,
              descriptor_bucket_labels(Map.get(descriptors, "vertical"))
            )

          derived_vertical_labels =
            designators_summary
            |> Map.get("vertical")
            |> case do
              %{bucket_labels: labels} -> labels
              _ -> nil
            end
            |> Kernel.||(derive_vertical_labels(series))

          %{
            id: id,
            widget_type: widget_type,
            mode: mode,
            chart_type: chart_type,
            path_aggregation: path_aggregation,
            color_mode: color_mode,
            color_config: color_config,
            legend: legend,
            bucket_labels: horizontal_descriptor.bucket_labels,
            vertical_bucket_labels: derived_vertical_labels,
            series: series,
            designator: Map.get(designators_summary, "horizontal", %{}),
            designators: designators_summary,
            points?: mode == "3d",
            errors: designator_errors
          }
      end
    end
  end

  defp series_for_paths(series_struct, paths, descriptor, item, color_map) do
    slice_count = slice_count(series_struct)

    Enum.map(paths, fn path ->
      bucket_map = bucket_totals(series_struct, path, slice_count)

      values =
        Enum.map(descriptor.bucket_labels, fn label ->
          value = Map.get(bucket_map, label, 0.0)
          %{bucket: label, value: value}
        end)

      %{
        name: path_label(path, item),
        path: path,
        color: Map.get(color_map, path),
        values: values
      }
    end)
  end

  defp derive_vertical_labels(series) do
    labels =
      series
      |> List.wrap()
      |> Enum.flat_map(fn s ->
        s
        |> Map.get(:points, [])
        |> Enum.map(& &1.bucket_y)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case labels do
      [] -> nil
      _ -> labels
    end
  end

  defp series_for_paths_3d(
         series_struct,
         paths,
         horizontal_descriptor,
         vertical_descriptor,
         item,
         color_map
       ) do
    Enum.map(paths, fn path ->
      matrix = bucket_matrix(series_struct, path, horizontal_descriptor, vertical_descriptor)

      points =
        matrix
        |> Enum.flat_map(fn {x_bucket, y_map} ->
          Enum.map(y_map, fn {y_bucket, value} ->
            %{
              bucket_x: x_bucket,
              bucket_y: y_bucket,
              value: value
            }
          end)
        end)

      %{
        name: path_label(path, item),
        path: path,
        color: Map.get(color_map, path),
        points: points
      }
    end)
  end

  defp maybe_aggregate_path_series(series, _mode, "none", _horizontal_labels, _vertical_labels),
    do: series

  defp maybe_aggregate_path_series(
         series,
         _mode,
         _aggregation,
         _horizontal_labels,
         _vertical_labels
       )
       when not is_list(series) or length(series) <= 1,
       do: series

  defp maybe_aggregate_path_series(series, "3d", aggregation, horizontal_labels, vertical_labels) do
    point_maps = Enum.map(series, &series_points_map/1)

    keys =
      point_maps
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    points =
      keys
      |> Enum.map(fn {bucket_x, bucket_y} ->
        values = Enum.map(point_maps, fn map -> Map.get(map, {bucket_x, bucket_y}, 0.0) end)
        value = aggregate_values(values, aggregation)

        %{
          bucket_x: bucket_x,
          bucket_y: bucket_y,
          value: value
        }
      end)
      |> Enum.filter(fn point -> not is_nil(point.value) end)
      |> sort_points(horizontal_labels, vertical_labels)

    [
      %{
        name: aggregation_series_name(aggregation),
        path: "__aggregate__",
        color: aggregated_series_color(series),
        points: points
      }
    ]
  end

  defp maybe_aggregate_path_series(
         series,
         _mode,
         aggregation,
         horizontal_labels,
         _vertical_labels
       ) do
    value_maps = Enum.map(series, &series_values_map/1)

    labels =
      case List.wrap(horizontal_labels) do
        [] ->
          value_maps
          |> Enum.flat_map(&Map.keys/1)
          |> Enum.uniq()

        list ->
          list
      end

    values =
      Enum.map(labels, fn label ->
        bucket_values = Enum.map(value_maps, fn map -> Map.get(map, label, 0.0) end)

        %{
          bucket: label,
          value: aggregate_values(bucket_values, aggregation)
        }
      end)

    [
      %{
        name: aggregation_series_name(aggregation),
        path: "__aggregate__",
        color: aggregated_series_color(series),
        values: values
      }
    ]
  end

  defp series_values_map(series) do
    series
    |> Map.get(:values, [])
    |> Enum.reduce(%{}, fn entry, acc ->
      bucket =
        entry
        |> Map.get(:bucket, Map.get(entry, "bucket", ""))
        |> to_string()
        |> String.trim()

      if bucket == "" do
        acc
      else
        value = entry |> Map.get(:value, Map.get(entry, "value")) |> normalize_number()
        Map.put(acc, bucket, value)
      end
    end)
  end

  defp series_points_map(series) do
    series
    |> Map.get(:points, [])
    |> Enum.reduce(%{}, fn entry, acc ->
      bucket_x =
        entry
        |> Map.get(:bucket_x, Map.get(entry, "bucket_x", ""))
        |> to_string()
        |> String.trim()

      bucket_y =
        entry
        |> Map.get(:bucket_y, Map.get(entry, "bucket_y", ""))
        |> to_string()
        |> String.trim()

      cond do
        bucket_x == "" or bucket_y == "" ->
          acc

        true ->
          value = entry |> Map.get(:value, Map.get(entry, "value")) |> normalize_number()
          Map.update(acc, {bucket_x, bucket_y}, value, &(&1 + value))
      end
    end)
  end

  defp aggregate_values([], _aggregation), do: 0.0

  defp aggregate_values(values, aggregation) do
    numeric = Enum.map(values, &normalize_number/1)

    case aggregation do
      "sum" -> Enum.sum(numeric)
      "min" -> Enum.min(numeric)
      "max" -> Enum.max(numeric)
      "mean" -> Enum.sum(numeric) / max(length(numeric), 1)
      _ -> Enum.sum(numeric)
    end
  end

  defp sort_points(points, horizontal_labels, vertical_labels) do
    horizontal_index =
      horizontal_labels
      |> List.wrap()
      |> Enum.with_index()
      |> Map.new()

    vertical_index =
      vertical_labels
      |> List.wrap()
      |> Enum.with_index()
      |> Map.new()

    Enum.sort_by(points, fn point ->
      {
        Map.get(horizontal_index, point.bucket_x, 1_000_000),
        Map.get(vertical_index, point.bucket_y, 1_000_000),
        point.bucket_x,
        point.bucket_y
      }
    end)
  end

  defp aggregation_series_name(aggregation) do
    case aggregation do
      "sum" -> "Sum"
      "mean" -> "Average"
      "min" -> "Min"
      "max" -> "Max"
      _ -> "Aggregate"
    end
  end

  defp aggregated_series_color(series) do
    series
    |> Enum.find_value(fn entry ->
      entry
      |> Map.get(:color)
      |> case do
        value when is_binary(value) ->
          trimmed = String.trim(value)
          if trimmed == "", do: nil, else: trimmed

        _ ->
          nil
      end
    end)
  end

  defp descriptor_bucket_labels(%{bucket_labels: labels}) when is_list(labels), do: labels
  defp descriptor_bucket_labels(_), do: []

  defp fallback_heatmap_color(paths, path_color_map) do
    paths
    |> Enum.find_value(fn path ->
      path_color_map
      |> Map.get(path)
      |> case do
        value when is_binary(value) ->
          trimmed = String.trim(value)
          if trimmed == "", do: nil, else: trimmed

        _ ->
          nil
      end
    end)
  end

  defp bucket_totals(series_struct, path, slice_count) do
    normalized_path = to_string(path || "") |> String.trim()
    stripped = strip_wildcard(normalized_path)

    transform_fn = fn key, value ->
      bucket =
        key
        |> to_string()
        |> bucket_label_for_path(stripped)

      {bucket, value}
    end

    series_struct
    |> Series.format_category(normalized_path, slice_count, transform_fn)
    |> reduce_bucket_maps()
  end

  defp bucket_matrix(series_struct, path, horizontal_descriptor, vertical_descriptor) do
    normalized_path = to_string(path || "") |> String.trim()

    clean_segments =
      normalized_path |> strip_wildcard() |> String.split(".") |> Enum.reject(&(&1 == ""))

    series_struct
    |> Map.get(:series, %{})
    |> Map.get(:values, [])
    |> Enum.reduce(%{}, fn data, acc ->
      case get_in(data, clean_segments) do
        %{} = map -> accumulate_matrix(map, acc, horizontal_descriptor, vertical_descriptor)
        _ -> acc
      end
    end)
  end

  defp accumulate_matrix(map, acc, horizontal_descriptor, vertical_descriptor) when is_map(map) do
    Enum.reduce(map, acc, fn {raw_x, raw_y_map}, matrix_acc ->
      x_bucket = normalize_bucket_key(raw_x, horizontal_descriptor.bucket_labels)

      cond do
        is_nil(x_bucket) ->
          matrix_acc

        is_map(raw_y_map) ->
          Enum.reduce(raw_y_map, matrix_acc, fn {raw_y, value}, inner ->
            y_bucket = normalize_bucket_key(raw_y, vertical_descriptor.bucket_labels)

            if is_nil(y_bucket) do
              inner
            else
              number = normalize_number(value)

              Map.update(inner, x_bucket, %{y_bucket => number}, fn ymap ->
                Map.update(ymap, y_bucket, number, &(&1 + number))
              end)
            end
          end)

        is_number(raw_y_map) ->
          number = normalize_number(raw_y_map)

          Map.update(matrix_acc, x_bucket, %{"total" => number}, fn ymap ->
            Map.update(ymap, "total", number, &(&1 + number))
          end)

        true ->
          matrix_acc
      end
    end)
  end

  defp accumulate_matrix(_other, acc, _horizontal_descriptor, _vertical_descriptor), do: acc

  defp normalize_bucket_key(value, valid_labels) do
    label =
      value
      |> format_bucket_label()
      |> String.trim()

    cond do
      label == "" -> nil
      label in valid_labels -> label
      true -> label
    end
  end

  defp ensure_points_for_3d(series, bucket_labels) do
    Enum.map(series, fn
      %{points: points} = s when is_list(points) and points != [] ->
        s

      %{values: values} = s when is_list(values) ->
        points =
          values
          |> Enum.map(fn %{bucket: bucket, value: value} ->
            %{
              bucket_x: bucket || List.first(bucket_labels) || "0",
              bucket_y: "total",
              value: normalize_number(value)
            }
          end)

        s
        |> Map.put(:points, points)
        |> Map.delete(:values)

      other ->
        other
    end)
  end

  defp reduce_bucket_maps(formatted) when is_map(formatted),
    do: accumulate_bucket_map(formatted, %{})

  defp reduce_bucket_maps(formatted) when is_list(formatted) do
    formatted
    |> Enum.reduce(%{}, fn map, acc -> accumulate_bucket_map(map, acc) end)
  end

  defp reduce_bucket_maps(_), do: %{}

  defp accumulate_bucket_map(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {bucket, value}, inner_acc ->
      label = bucket |> to_string() |> String.trim()
      number = normalize_number(value)
      Map.update(inner_acc, label, number, &(&1 + number))
    end)
  end

  defp accumulate_bucket_map(_, acc), do: acc

  defp normalized_paths(item) do
    raw_paths =
      case item["paths"] do
        list when is_list(list) -> list
        _ -> []
      end

    fallback_paths =
      case Map.get(item, "path") do
        nil -> []
        "" -> []
        value -> [value]
      end

    path_sources = if raw_paths == [], do: fallback_paths, else: raw_paths

    path_sources
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_mode(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "3d" -> "3d"
      _ -> "2d"
    end
  end

  defp normalize_chart_type(value, default) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "heatmap" -> "heatmap"
      "bar" -> "bar"
      _ when default == "heatmap" -> "heatmap"
      _ -> "bar"
    end
  end

  defp normalize_widget_type(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> case do
      "heatmap" -> "heatmap"
      _ -> "distribution"
    end
  end

  defp build_designators(designators) when is_map(designators) do
    Enum.reduce(designators, %{descriptors: %{}, errors: []}, fn {axis, config}, acc ->
      axis_key = normalize_axis_key(axis)

      cond do
        is_nil(axis_key) ->
          acc

        is_nil(config) ->
          acc

        true ->
          case build_designator(config) do
            {:ok, descriptor} ->
              %{acc | descriptors: Map.put(acc.descriptors, axis_key, descriptor)}

            {:error, error} ->
              %{acc | errors: acc.errors ++ [{axis_key, error}]}
          end
      end
    end)
  end

  defp build_designators(_), do: %{descriptors: %{}, errors: []}

  defp designator_error_messages(errors, mode) do
    relevant_axes =
      case mode do
        "3d" -> MapSet.new(["horizontal", "vertical"])
        _ -> MapSet.new(["horizontal"])
      end

    errors
    |> Enum.filter(fn {axis, _error} -> MapSet.member?(relevant_axes, axis) end)
    |> Enum.map(fn {axis, error} -> format_designator_error(axis, error) end)
  end

  defp format_designator_error(axis, error) do
    label =
      axis
      |> normalize_axis_key()
      |> case do
        nil -> "Designator"
        value -> "#{String.capitalize(value)} designator"
      end

    formatted_error =
      case error do
        list when is_list(list) -> Enum.join(list, ", ")
        other -> to_string(other)
      end

    "#{label}: #{formatted_error}"
  end

  defp summarize_designators(descriptors) do
    descriptors
    |> Enum.reduce(%{}, fn {axis, descriptor}, acc ->
      case normalize_axis_key(axis) do
        nil ->
          acc

        axis_key ->
          Map.put(acc, axis_key, %{
            type: descriptor.type,
            bucket_labels: descriptor.bucket_labels,
            config: descriptor.config
          })
      end
    end)
  end

  defp normalize_axis_key(key) do
    key
    |> case do
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      other -> other
    end
  end

  defp build_designator(%{"type" => type} = config) do
    case normalize_designator_type(type) do
      :custom -> build_custom_designator(config)
      :linear -> build_linear_designator(config)
      :geometric -> build_geometric_designator(config)
      _ -> {:error, "Unsupported designator type"}
    end
  end

  defp build_designator(_), do: {:error, "Designator configuration missing"}

  defp build_custom_designator(config) do
    buckets =
      config
      |> Map.get("buckets", [])
      |> Enum.map(&normalize_custom_bucket/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    cond do
      buckets == [] ->
        {:error, "Custom designator requires at least one bucket value"}

      Enum.all?(buckets, &is_number/1) ->
        numeric_buckets = Enum.sort(buckets)
        labels = Enum.map(numeric_buckets, &format_bucket_label/1)
        overflow = (List.last(labels) || "0") <> "+"
        struct = Custom.new(numeric_buckets)

        {:ok,
         %{
           type: :custom,
           struct: struct,
           bucket_labels: labels ++ [overflow],
           config: %{buckets: numeric_buckets}
         }}

      true ->
        labels =
          buckets
          |> Enum.map(&format_bucket_label/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        if labels == [] do
          {:error, "Custom designator requires at least one bucket value"}
        else
          {:ok,
           %{
             type: :custom,
             struct: nil,
             bucket_labels: labels,
             config: %{buckets: labels}
           }}
        end
    end
  end

  defp build_linear_designator(config) do
    min = parse_number(Map.get(config, "min"))
    max = parse_number(Map.get(config, "max"))
    step = parse_number(Map.get(config, "step"))

    cond do
      is_nil(min) or is_nil(max) or is_nil(step) ->
        {:error, "Linear designator requires min, max, and step values"}

      step <= 0 ->
        {:error, "Linear designator step must be greater than zero"}

      min > max ->
        {:error, "Linear designator min must be <= max"}

      true ->
        struct = Linear.new(trunc(min), trunc(max), step)
        bucket_labels = linear_bucket_labels(min, max, step)

        {:ok,
         %{
           type: :linear,
           struct: struct,
           bucket_labels: bucket_labels,
           config: %{min: min, max: max, step: step}
         }}
    end
  end

  defp build_geometric_designator(config) do
    min = parse_number(Map.get(config, "min"))
    max = parse_number(Map.get(config, "max"))

    cond do
      is_nil(min) or is_nil(max) ->
        {:error, "Geometric designator requires min and max values"}

      min > max ->
        {:error, "Geometric designator min must be <= max"}

      true ->
        struct = Geometric.new(min, max)
        bucket_labels = geometric_bucket_labels(struct)

        {:ok,
         %{
           type: :geometric,
           struct: struct,
           bucket_labels: bucket_labels,
           config: %{min: struct.min, max: struct.max}
         }}
    end
  end

  defp linear_bucket_labels(min, max, step) do
    base_labels =
      min
      |> Stream.iterate(&(&1 + step))
      |> Enum.take_while(&(&1 <= max))
      |> Enum.map(&format_bucket_label/1)

    overflow = format_bucket_label(max) <> "+"
    Enum.uniq([format_bucket_label(min) | base_labels] ++ [overflow])
  end

  defp geometric_bucket_labels(%Geometric{} = designator) do
    min = designator.min
    max = designator.max

    max_power =
      max
      |> max(1.0)
      |> :math.log10()
      |> Float.floor()
      |> trunc()

    big_samples =
      for exp <- 0..max_power, multiplier <- [1, 2, 5], do: :math.pow(10, exp) * multiplier

    small_samples =
      for exp <- 1..4, multiplier <- [1, 5], do: multiplier / :math.pow(10, exp)

    samples =
      [min, max, min / 10, max * 1.2, 1.0, 0.5]
      |> Enum.concat(big_samples)
      |> Enum.concat(small_samples)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&abs/1)
      |> Enum.filter(&(&1 > 0))

    labels =
      samples
      |> Enum.map(&Geometric.designate(designator, &1))
      |> Enum.reject(&is_nil_or_empty/1)
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    sorted =
      labels
      |> Enum.sort_by(&bucket_sort_key/1)

    overflow =
      Geometric.designate(designator, max + abs(max) + 1)
      |> case do
        result when is_binary(result) -> String.trim(result)
        _ -> format_bucket_label(max) <> "+"
      end

    sorted
    |> Enum.reject(&String.ends_with?(&1, "+"))
    |> Kernel.++([overflow])
  end

  defp bucket_sort_key(label) do
    trimmed = String.trim(label || "")
    overflow = String.ends_with?(trimmed, "+")
    number = parse_number(trimmed |> String.trim_trailing("+")) || 0.0
    {number, overflow}
  end

  defp strip_wildcard(path) do
    cond do
      path == nil -> ""
      String.ends_with?(path, ".*") -> String.trim_trailing(path, ".*")
      true -> path
    end
  end

  defp bucket_label_for_path(full_key, base_path) do
    cond do
      base_path == "" ->
        last_segment(full_key)

      String.starts_with?(full_key, base_path <> ".") ->
        String.replace_prefix(full_key, base_path <> ".", "")

      true ->
        last_segment(full_key)
    end
  end

  defp last_segment(key) do
    key
    |> String.split(".")
    |> List.last()
    |> case do
      nil -> key
      value -> value
    end
  end

  defp slice_count(series_struct) do
    series_struct
    |> Map.get(:series, %{})
    |> case do
      series_map when is_map(series_map) ->
        values = Map.get(series_map, :values) || Map.get(series_map, "values") || []
        if is_list(values) and length(values) > 1, do: 2, else: 1

      _ ->
        1
    end
  end

  defp normalize_designator_type(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      "custom" -> :custom
      "linear" -> :linear
      "geometric" -> :geometric
      _ -> nil
    end
  end

  defp parse_number(value), do: SharedParse.parse_numeric_bucket(value)

  defp normalize_custom_bucket(value) when is_integer(value), do: value * 1.0
  defp normalize_custom_bucket(value) when is_float(value), do: value

  defp normalize_custom_bucket(value) when is_binary(value) do
    trimmed = String.trim(value)

    case trimmed do
      "" ->
        nil

      _ ->
        case SharedParse.parse_numeric_bucket(trimmed) do
          nil -> trimmed
          number -> number
        end
    end
  end

  defp normalize_custom_bucket(_), do: nil

  defp normalize_number(%Decimal{} = decimal), do: decimal |> Decimal.to_float()
  defp normalize_number(value) when is_integer(value), do: value * 1.0
  defp normalize_number(value) when is_float(value), do: value * 1.0
  defp normalize_number(_), do: 0.0

  defp format_bucket_label(value) when is_integer(value), do: Integer.to_string(value)

  defp format_bucket_label(value) when is_float(value) do
    cond do
      value >= 1_000_000_000 -> :erlang.float_to_binary(value, [:compact, decimals: 1])
      true -> trim_trailing_zero(:erlang.float_to_binary(value, decimals: 4))
    end
  end

  defp format_bucket_label(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> "0"
      other -> other
    end
  end

  defp format_bucket_label(_), do: "0"

  defp trim_trailing_zero(value) do
    value
    |> String.replace(~r/\.0+$/, "")
    |> String.replace(~r/(\.\d*?)0+$/, "\\1")
    |> String.trim_trailing(".")
  end

  defp path_label(path, item) do
    labels =
      item
      |> Map.get("path_labels", %{})
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), to_string(v)} end)

    Map.get(labels, path, path)
  end

  defp is_nil_or_empty(value) do
    is_nil(value) or (is_binary(value) and String.trim(value) == "")
  end
end
