defmodule TrifleApp.Components.DashboardWidgets.GroupExpansion do
  @moduledoc false

  alias TrifleApp.Components.DashboardWidgets.{Helpers, LayoutTree, MetricSeries, Registry}

  @wildcard_suffix ".*"
  @derived_group_key "_derived_group"
  @expanded_group_key "_expanded_group"
  @template_group_id_key "_template_group_id"
  @expansion_index_key "_group_expansion_index"
  @concrete_group_path_key "_concrete_group_path"
  @group_header_style_key "_group_header_style"

  def derived_group_key, do: @derived_group_key
  def expanded_group_key, do: @expanded_group_key
  def template_group_id_key, do: @template_group_id_key

  def derived?(item) when is_map(item) do
    truthy?(Map.get(item, @derived_group_key) || Map.get(item, :derived_group))
  end

  def derived?(_item), do: false

  def synthetic_id?(id) do
    id
    |> to_string()
    |> String.contains?("--expanded--")
  end

  def normalize_group_path(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.trim_leading(".")
    |> String.trim_trailing(".")
    |> case do
      "" -> nil
      path -> if valid_group_path?(path), do: path, else: nil
    end
  end

  def terminal_wildcard?(path) when is_binary(path) do
    String.ends_with?(path, @wildcard_suffix) and
      not String.contains?(String.trim_trailing(path, @wildcard_suffix), "*")
  end

  def terminal_wildcard?(_path), do: false

  def valid_group_path?(path) when is_binary(path) do
    cond do
      path == "" ->
        false

      terminal_wildcard?(path) ->
        valid_path_segments?(path)

      String.contains?(path, "*") ->
        false

      true ->
        valid_path_segments?(path)
    end
  end

  def valid_group_path?(_path), do: false

  defp valid_path_segments?(path) do
    path
    |> String.split(".")
    |> Enum.all?(&(&1 != ""))
  end

  def expand_root_items(items, stats \\ nil)

  def expand_root_items(items, stats) when is_list(items) do
    normalized = LayoutTree.normalize_root_items(items)

    if Enum.any?(normalized, &expanded?/1) do
      normalized
    else
      available_paths = MetricSeries.available_paths(stats)
      expansions = expansion_metadata(normalized, available_paths)

      normalized
      |> Enum.flat_map(fn item -> expand_root_item(item, available_paths) end)
      |> apply_expansion_offsets(expansions)
    end
  end

  def expand_root_items(_items, _stats), do: []

  def expanded?(item) when is_map(item) do
    truthy?(Map.get(item, @expanded_group_key) || Map.get(item, :expanded_group))
  end

  def expanded?(_item), do: false

  def persisted_items(items) when is_list(items) do
    items
    |> Enum.reject(&derived?/1)
    |> Enum.map(&drop_render_fields/1)
  end

  def persisted_items(_items), do: []

  defp expansion_metadata(items, available_paths) do
    items
    |> Enum.filter(&LayoutTree.group?/1)
    |> Enum.map(fn item ->
      path = group_path(item)
      count = length(resolved_group_paths(path, available_paths))
      height = layout_int(Map.get(item, "h"), 4)
      y = layout_int(Map.get(item, "y"), 0)

      %{
        id: group_id(item),
        y: y,
        bottom: y + height,
        height: height,
        extra: max(count - 1, 0) * height
      }
    end)
    |> Enum.reject(&(&1.extra <= 0))
  end

  defp expand_root_item(item, available_paths) do
    if LayoutTree.group?(item) do
      expand_group_item(item, available_paths)
    else
      [Registry.normalize_widget(item)]
    end
  end

  defp expand_group_item(item, available_paths) do
    group = LayoutTree.normalize_group_item(item)
    path = group_path(group)

    case resolved_group_paths(path, available_paths) do
      [] ->
        [mark_group_expanded(group, path, 0, false)]

      paths ->
        paths
        |> Enum.with_index()
        |> Enum.map(fn {concrete_path, index} ->
          derived? = index > 0

          group
          |> apply_group_path(concrete_path, index, derived?)
          |> maybe_synthetic_group(index, concrete_path)
        end)
    end
  end

  defp resolved_group_paths(nil, _available_paths), do: []

  defp resolved_group_paths(path, available_paths) do
    cond do
      terminal_wildcard?(path) ->
        wildcard_prefixes(path, available_paths)

      path != "" ->
        [path]

      true ->
        []
    end
  end

  defp wildcard_prefixes(path, available_paths) do
    base = String.trim_trailing(path, @wildcard_suffix)

    available_paths
    |> Enum.map(&to_string/1)
    |> Enum.flat_map(fn available_path ->
      cond do
        base == "" ->
          available_path
          |> String.split(".", parts: 2)
          |> List.first()
          |> List.wrap()

        available_path == base ->
          []

        String.starts_with?(available_path, base <> ".") ->
          available_path
          |> String.replace_prefix(base <> ".", "")
          |> String.split(".", parts: 2)
          |> List.first()
          |> case do
            nil -> []
            "" -> []
            segment -> [base <> "." <> segment]
          end

        true ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp apply_group_path(group, concrete_path, index, derived?) do
    group
    |> mark_group_expanded(concrete_path, index, derived?)
    |> Map.update!("children", fn children ->
      Enum.map(children, &prefix_child_widget(&1, concrete_path, derived?, index))
    end)
    |> Map.put("title", expanded_title(group, concrete_path))
  end

  defp mark_group_expanded(group, concrete_path, index, derived?) do
    group =
      group
      |> Map.put(@expanded_group_key, true)
      |> Map.put(@expansion_index_key, index)
      |> put_optional(@concrete_group_path_key, concrete_path)
      |> put_optional(@template_group_id_key, group_id(group))
      |> maybe_put_derived(derived?)

    Map.put(group, @group_header_style_key, group_header_style_payload(group))
  end

  defp group_header_style_payload(group) do
    surface = Helpers.group_header_surface_colors(group)

    %{
      "default" => Map.get(surface, :default?, true),
      "background" => Map.get(surface, :background),
      "text" => Map.get(surface, :text),
      "border" => Map.get(surface, :border)
    }
  end

  defp maybe_put_derived(group, true), do: Map.put(group, @derived_group_key, true)
  defp maybe_put_derived(group, false), do: group

  defp maybe_synthetic_group(group, 0, _concrete_path), do: group

  defp maybe_synthetic_group(group, index, concrete_path) do
    template_id = group_id(group)
    synthetic_id = synthetic_id(template_id, concrete_path, index)

    group
    |> Map.put("id", synthetic_id)
    |> Map.update!("children", fn children ->
      Enum.map(children, &synthetic_child_id(&1, synthetic_id))
    end)
  end

  defp prefix_child_widget(child, nil, _derived?, _index), do: Registry.normalize_widget(child)
  defp prefix_child_widget(child, "", _derived?, _index), do: Registry.normalize_widget(child)

  defp prefix_child_widget(child, concrete_path, _derived?, _index) do
    child = Registry.normalize_widget(child)

    if MetricSeries.metric_widget?(child) do
      child
      |> MetricSeries.normalize_widget()
      |> Map.update("series", [], fn rows ->
        Enum.map(rows, &prefix_series_row(&1, concrete_path))
      end)
    else
      child
    end
  end

  defp prefix_series_row(row, concrete_path) when is_map(row) do
    case MetricSeries.row_kind(row) do
      "nested" ->
        path = MetricSeries.row_path(row)
        Map.put(row, "path", prefixed_path(concrete_path, path))

      _ ->
        row
    end
  end

  defp prefix_series_row(row, _concrete_path), do: row

  defp prefixed_path(prefix, path) do
    path = to_string(path) |> String.trim()

    cond do
      path == "" ->
        prefix

      path == "$" ->
        prefix

      String.starts_with?(path, "$.") ->
        prefixed_path(prefix, String.replace_prefix(path, "$.", ""))

      prefix in [nil, ""] ->
        path

      true ->
        prefix <> "." <> path
    end
  end

  defp synthetic_child_id(child, synthetic_group_id) do
    original_id = Map.get(child, "id", Map.get(child, :id, "widget"))
    Map.put(child, "id", synthetic_group_id <> "--" <> safe_id(original_id))
  end

  defp synthetic_id(template_id, concrete_path, index) do
    [template_id || "group", "expanded", index, concrete_path]
    |> Enum.map(&safe_id/1)
    |> Enum.join("--")
  end

  defp safe_id(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "item"
      safe -> safe
    end
  end

  defp expanded_title(group, concrete_path) do
    title =
      group
      |> Map.get("title", LayoutTree.default_group_title())
      |> to_string()
      |> String.trim()
      |> case do
        "" -> LayoutTree.default_group_title()
        value -> value
      end

    if concrete_path in [nil, ""] do
      title
    else
      title <> ": " <> concrete_path
    end
  end

  defp apply_expansion_offsets(items, expansions) do
    Enum.map(items, fn item ->
      y = layout_int(Map.get(item, "y"), 0)
      own_template_id = Map.get(item, @template_group_id_key)

      offset =
        expansions
        |> Enum.reject(&(&1.id == own_template_id))
        |> Enum.filter(&(y >= &1.bottom))
        |> Enum.reduce(0, &(&1.extra + &2))

      item
      |> Map.update("y", y + offset, fn value -> layout_int(value, y) + offset end)
      |> maybe_stack_derived_group()
    end)
  end

  defp maybe_stack_derived_group(%{@derived_group_key => true} = group) do
    index = layout_int(Map.get(group, @expansion_index_key), 0)
    height = layout_int(Map.get(group, "h"), 4)

    Map.update(group, "y", index * height, fn y -> layout_int(y, 0) + index * height end)
  end

  defp maybe_stack_derived_group(group), do: group

  defp drop_render_fields(item) when is_map(item) do
    cleaned =
      Map.drop(item, [
        @derived_group_key,
        @expanded_group_key,
        @template_group_id_key,
        @expansion_index_key,
        @concrete_group_path_key,
        @group_header_style_key
      ])

    if Map.has_key?(cleaned, "children") do
      Map.update!(cleaned, "children", fn children ->
        children
        |> List.wrap()
        |> Enum.map(&drop_render_fields/1)
      end)
    else
      cleaned
    end
  end

  defp drop_render_fields(other), do: other

  defp group_path(group) do
    group
    |> Map.get("group_path", Map.get(group, :group_path))
    |> normalize_group_path()
  end

  defp group_id(group), do: Map.get(group, "id", Map.get(group, :id))

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, ""), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp layout_int(value, _default) when is_integer(value), do: value

  defp layout_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  defp layout_int(_value, default), do: default

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_), do: false
end
