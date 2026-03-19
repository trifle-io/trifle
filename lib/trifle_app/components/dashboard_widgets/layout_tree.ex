defmodule TrifleApp.Components.DashboardWidgets.LayoutTree do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.Registry

  @group_type "group"

  def group?(item) when is_map(item), do: normalized_type(item) == @group_type
  def group?(_), do: false

  def widget?(item) when is_map(item), do: normalized_type(item) != @group_type
  def widget?(_), do: false

  def normalize_root_items(items) when is_list(items) do
    items
    |> Enum.flat_map(&normalize_root_item/1)
  end

  def normalize_root_items(_other), do: []

  def root_items_from_dashboard(dashboard) when is_map(dashboard) do
    dashboard
    |> dashboard_payload()
    |> Map.get("grid", [])
    |> normalize_root_items()
  end

  def root_items_from_dashboard(_other), do: []

  def flatten_widgets(items) when is_list(items) do
    Enum.flat_map(items, fn item ->
      cond do
        group?(item) ->
          item
          |> group_children()
          |> flatten_widgets()

        widget?(item) ->
          [Registry.normalize_widget(item)]

        true ->
          []
      end
    end)
  end

  def flatten_widgets(_other), do: []

  def find_node(items, id) when is_list(items) do
    needle = normalize_id(id)

    Enum.find_value(items, fn item ->
      cond do
        normalize_id(Map.get(item, "id", Map.get(item, :id))) == needle ->
          item

        group?(item) ->
          find_node(group_children(item), needle)

        true ->
          nil
      end
    end)
  end

  def find_node(_items, _id), do: nil

  def update_node(items, id, fun) when is_list(items) and is_function(fun, 1) do
    needle = normalize_id(id)

    Enum.map(items, fn item ->
      item_id = normalize_id(Map.get(item, "id", Map.get(item, :id)))

      cond do
        item_id == needle ->
          fun.(item)

        group?(item) ->
          Map.put(item, "children", update_node(group_children(item), needle, fun))

        true ->
          item
      end
    end)
  end

  def update_node(items, _id, _fun), do: items

  def group_children(item) when is_map(item) do
    case Map.get(item, "children", Map.get(item, :children, [])) do
      list when is_list(list) -> normalize_group_children(list)
      _ -> []
    end
  end

  def group_children(_item), do: []

  def normalize_group_item(item) when is_map(item) do
    item
    |> Map.put("type", @group_type)
    |> Map.put("title", group_title(item))
    |> Map.put("children", group_children(item))
  end

  def normalize_group_item(item), do: item

  def default_group_title, do: "Widget Group"

  defp normalize_root_item(item) when is_map(item) do
    cond do
      group?(item) ->
        [normalize_group_item(item)]

      widget?(item) ->
        [Registry.normalize_widget(item)]

      true ->
        []
    end
  end

  defp normalize_root_item(_other), do: []

  defp normalize_group_children(children) when is_list(children) do
    children
    |> Enum.flat_map(fn child ->
      cond do
        group?(child) ->
          group_children(child)

        widget?(child) ->
          [Registry.normalize_widget(child)]

        true ->
          []
      end
    end)
  end

  defp dashboard_payload(dashboard) when is_map(dashboard) do
    payload = Map.get(dashboard, :payload) || Map.get(dashboard, "payload") || %{}

    case payload do
      %{} = map -> Map.put_new(map, "grid", [])
      _ -> %{"grid" => []}
    end
  end

  defp normalized_type(item) when is_map(item) do
    item
    |> Map.get("type")
    |> case do
      nil -> Map.get(item, :type)
      value -> value
    end
    |> to_string()
    |> String.downcase()
  end

  defp normalized_type(_item), do: ""

  defp group_title(item) do
    item
    |> Map.get("title", Map.get(item, :title, default_group_title()))
    |> to_string()
    |> String.trim()
    |> case do
      "" -> default_group_title()
      value -> value
    end
  end

  defp normalize_id(nil), do: nil
  defp normalize_id(value) when is_binary(value), do: value
  defp normalize_id(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_id(value), do: to_string(value)
end
