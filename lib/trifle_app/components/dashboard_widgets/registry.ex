defmodule TrifleApp.Components.DashboardWidgets.Registry do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.Types

  @widget_types [
    Types.Kpi,
    Types.Timeseries,
    Types.Category,
    Types.Table,
    Types.Text,
    Types.List,
    Types.Distribution,
    Types.Heatmap
  ]

  @spec modules() :: [module()]
  def modules, do: @widget_types

  @spec widget_type(map() | String.t() | atom() | nil) :: String.t()
  def widget_type(nil), do: "kpi"

  def widget_type(value) when is_binary(value) do
    value
    |> String.downcase()
    |> case do
      "" -> "kpi"
      type -> type
    end
  end

  def widget_type(value) when is_atom(value), do: value |> Atom.to_string() |> widget_type()

  def widget_type(widget) when is_map(widget) do
    widget
    |> Map.get("type")
    |> case do
      nil -> Map.get(widget, "widget_type")
      value -> value
    end
    |> case do
      nil -> Map.get(widget, :type)
      value -> value
    end
    |> case do
      nil -> Map.get(widget, :widget_type, "kpi")
      value -> value
    end
    |> widget_type()
  end

  def widget_type(_other), do: "kpi"

  @spec type_module(String.t() | atom() | map() | nil) :: module()
  def type_module(type_or_widget) do
    normalized_type = widget_type(type_or_widget)

    Enum.find(@widget_types, Types.Kpi, fn module ->
      module.type() == normalized_type
    end)
  end

  @spec editor_module(String.t() | atom() | map() | nil) :: module()
  def editor_module(type_or_widget) do
    type_or_widget
    |> type_module()
    |> apply(:editor_module, [])
  end

  @spec normalize_widget(map()) :: map()
  def normalize_widget(widget) when is_map(widget) do
    module = type_module(widget)

    if function_exported?(module, :normalize_widget, 1) do
      module.normalize_widget(widget)
    else
      widget
    end
  end

  def normalize_widget(other), do: other

  @spec client_payload(String.t(), String.t(), map()) :: map() | nil
  def client_payload(type, widget_id, dataset_maps) do
    type
    |> type_module()
    |> apply(:client_payload, [widget_id, dataset_maps])
  end

  @doc """
  Fetches a widget dataset payload by bucket and widget id from a dataset maps struct.
  """
  @spec fetch_dataset(map(), atom(), any()) :: any()
  def fetch_dataset(dataset_maps, key, id) when is_map(dataset_maps) and is_atom(key) do
    dataset_maps
    |> Map.get(key, %{})
    |> case do
      map when is_map(map) ->
        case Map.get(map, id) do
          nil -> Map.get(map, to_string(id))
          value -> value
        end

      _ ->
        nil
    end
  end

  def fetch_dataset(_dataset_maps, _key, _id), do: nil
end
