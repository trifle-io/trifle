defmodule Trifle.Chat.InlineDashboard do
  @moduledoc """
  Builds and rehydrates inline dashboard visualizations used inside chat.
  """

  alias Ecto.UUID
  alias Trifle.Chat.DashboardSpec
  alias Trifle.Stats.Series
  alias TrifleApp.Components.DashboardWidgets.{Registry, WidgetData, WidgetView}

  @type source_meta :: map()
  @type timeframe_meta :: map()
  @type visualization :: map()

  @spec build_visualization(source_meta(), String.t(), list(), map(), keyword()) ::
          {:ok, visualization()} | {:error, map()}
  def build_visualization(source_meta, metric_key, grid, series_snapshot, opts \\ [])

  def build_visualization(source_meta, metric_key, grid, series_snapshot, opts)
      when is_map(source_meta) and is_binary(metric_key) and is_list(grid) and is_map(series_snapshot) do
    with {:ok, normalized_grid} <- normalize_grid(grid) do
      dashboard_id = "inline-dashboard-" <> UUID.generate()
      title = resolve_title(opts, metric_key)
      timeframe = opts |> Keyword.get(:timeframe, %{}) |> stringify_keys()
      default_timeframe = Keyword.get(opts, :default_timeframe)
      default_granularity = Keyword.get(opts, :default_granularity)

      dashboard = %{
        "id" => dashboard_id,
        "name" => title,
        "key" => metric_key,
        "default_timeframe" => default_timeframe,
        "default_granularity" => default_granularity,
        "payload" => %{"grid" => normalized_grid}
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

      visualization = %{
        "id" => dashboard_id,
        "type" => "dashboard",
        "title" => title,
        "dashboard" => dashboard,
        "source" => stringify_keys(source_meta),
        "metric_key" => metric_key,
        "timeframe" => timeframe,
        "series_snapshot" => stringify_keys(series_snapshot),
        "widget_spec_version" => DashboardSpec.version()
      }

      {:ok, visualization}
    end
  end

  def build_visualization(_source_meta, _metric_key, _grid, _series_snapshot, _opts) do
    {:error, error("Dashboard visualization requires source metadata, metric key, grid, and series snapshot.")}
  end

  @spec normalize_grid(list()) :: {:ok, list()} | {:error, map()}
  def normalize_grid(grid) when is_list(grid) do
    state = %{x: 0, y: 0, row_h: 0, max_y: 0, occupied: MapSet.new()}

    grid
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, [], state}, fn {item, index}, {:ok, acc, layout_state} ->
      case normalize_widget(item, index, layout_state) do
        {:ok, normalized, next_state} -> {:cont, {:ok, acc ++ [normalized], next_state}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized, _layout_state} -> {:ok, normalized}
      {:error, reason} -> {:error, reason}
    end
  end

  def normalize_grid(_other), do: {:error, error("grid must be an array of widget objects.")}

  @spec render_state(map()) :: {:ok, map()} | {:error, map()}
  def render_state(visualization) when is_map(visualization) do
    with {:ok, dashboard} <- dashboard_from_visualization(visualization),
         {:ok, series} <- series_from_snapshot(visualization["series_snapshot"] || visualization[:series_snapshot]) do
      grid_items = WidgetView.grid_items(dashboard)

      dataset_maps =
        series
        |> WidgetData.datasets(grid_items)
        |> WidgetData.dataset_maps()

      {:ok,
       %{
         dashboard: dashboard,
         stats: series,
         dataset_maps: dataset_maps
       }}
    end
  end

  def render_state(_other), do: {:error, error("Invalid dashboard visualization payload.")}

  @spec series_from_snapshot(map()) :: {:ok, Series.t()} | {:error, map()}
  def series_from_snapshot(snapshot) when is_map(snapshot) do
    timestamps =
      snapshot
      |> value_for("at")
      |> List.wrap()
      |> Enum.map(&parse_timestamp/1)
      |> Enum.reject(&is_nil/1)

    values =
      snapshot
      |> value_for("values")
      |> List.wrap()

    if timestamps == [] and values == [] do
      {:error, error("Dashboard series snapshot is empty.")}
    else
      {:ok, Series.new(%{at: timestamps, values: values})}
    end
  end

  def series_from_snapshot(_other), do: {:error, error("Dashboard series snapshot is missing.")}

  @spec has_data?(map()) :: boolean()
  def has_data?(visualization) when is_map(visualization) do
    case visualization["series_snapshot"] || visualization[:series_snapshot] do
      %{} = snapshot ->
        snapshot
        |> value_for("at")
        |> List.wrap()
        |> Enum.any?()

      _ ->
        false
    end
  end

  def has_data?(_), do: false

  defp normalize_widget(item, index, layout_state) when is_map(item) do
    widget =
      item
      |> stringify_keys()
      |> Map.put("type", Registry.widget_type(item))
      |> ensure_widget_id(index)
      |> ensure_layout_defaults()
      |> Registry.normalize_widget()

    widget_type = Map.get(widget, "type")

    cond do
      not DashboardSpec.supported_type?(widget_type) ->
        {:error, error("Unsupported dashboard widget type: #{inspect(widget_type)}.")}

      true ->
        with :ok <- validate_required_fields(widget, widget_type) do
          {positioned_widget, next_layout_state} = position_widget(widget, layout_state)
          {:ok, positioned_widget, next_layout_state}
        end
    end
  end

  defp normalize_widget(_item, _index, _layout_state) do
    {:error, error("Every dashboard widget must be a JSON object.")}
  end

  defp ensure_widget_id(widget, index) do
    case Map.get(widget, "id") do
      id when is_binary(id) and id != "" ->
        Map.put(widget, "id", id)

      _ ->
        Map.put(widget, "id", "widget-" <> Integer.to_string(index + 1))
    end
  end

  defp ensure_layout_defaults(widget) do
    defaults =
      widget
      |> Map.get("type")
      |> DashboardSpec.widget_spec()
      |> case do
        %{defaults: widget_defaults} -> widget_defaults
        _ -> %{}
      end

    defaults
    |> Enum.reduce(widget, fn {key, value}, acc ->
      Map.put_new(acc, to_string(key), value)
    end)
    |> put_int_default("w", DashboardSpec.default_layout(Map.get(widget, "type")).w)
    |> put_int_default("h", DashboardSpec.default_layout(Map.get(widget, "type")).h)
  end

  defp validate_required_fields(widget, widget_type) do
    missing? =
      widget_type
      |> DashboardSpec.required_one_of()
      |> Enum.find(fn field_group ->
        Enum.all?(field_group, fn field -> blank_field?(widget, field) end)
      end)

    case missing? do
      nil ->
        :ok

      fields ->
        {:error,
         error(
           "Widget #{inspect(Map.get(widget, "id"))} of type #{widget_type} requires at least one of: #{Enum.join(fields, ", ")}."
         )}
    end
  end

  defp position_widget(widget, layout_state) do
    if has_explicit_position?(widget) do
      widget
      |> clamp_widget_frame()
      |> reserve_manual_widget(layout_state)
    else
      auto_place_widget(widget, layout_state)
    end
  end

  defp reserve_manual_widget(widget, layout_state) do
    width = Map.get(widget, "w", 1)
    height = Map.get(widget, "h", 1)
    x = Map.get(widget, "x", 0)
    start_y = Map.get(widget, "y", 0)

    y =
      Stream.iterate(start_y, &(&1 + 1))
      |> Enum.find(fn candidate_y ->
        widget_fits?(layout_state, x, candidate_y, width, height)
      end)

    positioned = Map.put(widget, "y", y)
    {positioned, reserve_widget(layout_state, positioned)}
  end

  defp auto_place_widget(widget, layout_state) do
    width = clamp_widget_size(Map.get(widget, "w"), 3)
    height = clamp_widget_size(Map.get(widget, "h"), 2)
    state = normalize_auto_cursor(layout_state, width)
    {x, y} = find_next_position(state, width, height)

    positioned =
      widget
      |> Map.put("x", x)
      |> Map.put("y", y)
      |> Map.put("w", width)
      |> Map.put("h", height)

    next_state =
      state
      |> reserve_widget(positioned)
      |> Map.put(:x, x + width)
      |> Map.put(:y, y)
      |> Map.put(:row_h, if(y == state.y, do: max(state.row_h, height), else: height))

    {positioned, next_state}
  end

  defp normalize_auto_cursor(%{x: x, y: y, row_h: row_h} = state, width) do
    if x + width > 12 do
      %{state | x: 0, y: y + max(row_h, 1), row_h: 0}
    else
      state
    end
  end

  defp find_next_position(state, width, height) do
    start_x = min(state.x, max(12 - width, 0))
    start_y = state.y

    Stream.iterate(start_y, &(&1 + 1))
    |> Enum.reduce_while(nil, fn candidate_y, _acc ->
      x_range =
        if candidate_y == start_y do
          start_x..max(12 - width, 0)
        else
          0..max(12 - width, 0)
        end

      case Enum.find(x_range, &widget_fits?(state, &1, candidate_y, width, height)) do
        nil -> {:cont, nil}
        candidate_x -> {:halt, {candidate_x, candidate_y}}
      end
    end)
  end

  defp reserve_widget(layout_state, widget) do
    x = Map.get(widget, "x", 0)
    y = Map.get(widget, "y", 0)
    width = Map.get(widget, "w", 1)
    height = Map.get(widget, "h", 1)
    bottom = y + height

    occupied =
      x
      |> occupied_cells(y, width, height)
      |> Enum.reduce(layout_state.occupied || MapSet.new(), fn cell, acc -> MapSet.put(acc, cell) end)

    %{layout_state | occupied: occupied, max_y: max(layout_state.max_y, bottom)}
  end

  defp widget_fits?(layout_state, x, y, width, height) do
    x >= 0 and y >= 0 and x + width <= 12 and
      Enum.all?(occupied_cells(x, y, width, height), fn cell ->
        not MapSet.member?(layout_state.occupied || MapSet.new(), cell)
      end)
  end

  defp occupied_cells(x, y, width, height) do
    for current_y <- y..(y + height - 1),
        current_x <- x..(x + width - 1) do
      {current_x, current_y}
    end
  end

  defp clamp_widget_frame(widget) do
    width = clamp_widget_size(Map.get(widget, "w"), 3)
    height = clamp_widget_size(Map.get(widget, "h"), 2)
    x = clamp_coordinate(Map.get(widget, "x"), max(12 - width, 0))
    y = clamp_coordinate(Map.get(widget, "y"))

    widget
    |> Map.put("w", width)
    |> Map.put("h", height)
    |> Map.put("x", x)
    |> Map.put("y", y)
  end

  defp has_explicit_position?(widget) do
    is_integer(Map.get(widget, "x")) and Map.get(widget, "x") >= 0 and
      is_integer(Map.get(widget, "y")) and Map.get(widget, "y") >= 0
  end

  defp clamp_coordinate(value, max_value \\ nil)

  defp clamp_coordinate(value, max_value) when is_integer(value) and value >= 0 and is_integer(max_value) do
    min(value, max_value)
  end

  defp clamp_coordinate(value, _max_value) when is_integer(value) and value >= 0, do: value

  defp clamp_coordinate(_value, max_value) when is_integer(max_value), do: min(0, max_value)
  defp clamp_coordinate(_value, _max_value), do: 0

  defp clamp_widget_size(value, _fallback) when is_integer(value) and value >= 1,
    do: min(value, 12)

  defp clamp_widget_size(value, fallback) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} when int >= 1 -> min(int, 12)
      _ -> fallback
    end
  end

  defp clamp_widget_size(_value, fallback), do: fallback

  defp put_int_default(widget, key, default) do
    case Map.get(widget, key) do
      value when is_integer(value) and value >= 1 -> widget
      _ -> Map.put(widget, key, default)
    end
  end

  defp blank_field?(widget, "path") do
    widget
    |> Map.get("path")
    |> blank_value?()
  end

  defp blank_field?(widget, "paths") do
    widget
    |> Map.get("paths")
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Kernel.==([])
  end

  defp blank_field?(widget, field) do
    widget
    |> Map.get(field)
    |> blank_value?()
  end

  defp blank_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_value?(nil), do: true
  defp blank_value?([]), do: true
  defp blank_value?(_), do: false

  defp resolve_title(opts, metric_key) do
    case Keyword.get(opts, :title) do
      title when is_binary(title) and title != "" -> title
      _ -> metric_key <> " Dashboard"
    end
  end

  defp dashboard_from_visualization(visualization) do
    case visualization["dashboard"] || visualization[:dashboard] do
      %{} = dashboard ->
        {:ok,
         %{
           id: value_for(dashboard, "id") || "inline-dashboard",
           name: value_for(dashboard, "name") || "Inline Dashboard",
           key: value_for(dashboard, "key") || "",
           default_timeframe: value_for(dashboard, "default_timeframe"),
           default_granularity: value_for(dashboard, "default_granularity"),
           payload: stringify_keys(value_for(dashboard, "payload") || %{})
         }}

      _ ->
        {:error, error("Dashboard payload is missing.")}
    end
  end

  defp parse_timestamp(%DateTime{} = dt), do: dt

  defp parse_timestamp(%NaiveDateTime{} = naive) do
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp parse_timestamp(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} ->
        dt

      {:error, _reason} ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          {:error, _} -> nil
        end
    end
  end

  defp parse_timestamp(_value), do: nil

  defp value_for(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp value_for(_map, _key), do: nil

  defp stringify_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, inner} -> {to_string(key), stringify_keys(inner)} end)
    |> Map.new()
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value), do: value

  defp error(message) do
    %{
      status: "error",
      error: message
    }
  end
end
