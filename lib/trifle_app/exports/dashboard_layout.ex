defmodule TrifleApp.Exports.DashboardLayout do
  @moduledoc """
  Builds export layouts for Dashboards by translating their GridStack payload
  and datasets into a standalone rendering specification.
  """

  alias Trifle.Exports.Series, as: SeriesExport
  alias Trifle.Organizations
  alias Trifle.Stats.Source
  alias TrifleApp.Components.DashboardWidgets.{WidgetData, WidgetView}
  alias TrifleApp.Exports.Layout
  alias TrifleApp.TimeframeParsing
  alias TrifleApp.TimeframeParsing.Url, as: UrlParsing

  @default_viewport %{width: 1366, height: 900}
  @widget_viewport %{width: 1024, height: 768}

  @type opts :: [
          params: map(),
          theme: Layout.theme(),
          viewport: %{width: pos_integer(), height: pos_integer()}
        ]

  @doc """
  Builds a layout for the given dashboard struct.
  """
  @spec build(Organizations.Dashboard.t(), opts()) ::
          {:ok, Layout.t()} | {:error, term()}
  def build(%Organizations.Dashboard{} = dashboard, opts \\ []) do
    do_build(dashboard, opts)
  end

  @doc """
  Builds a layout for a single widget within the dashboard payload.
  """
  @spec build_widget(Organizations.Dashboard.t(), String.t(), opts()) ::
          {:ok, Layout.t()} | {:error, term()}
  def build_widget(%Organizations.Dashboard{} = dashboard, widget_id, opts \\ []) do
    opts = Keyword.put(opts, :selected_widget_id, widget_id)
    do_build(dashboard, opts)
  end

  defp do_build(dashboard, opts) do
    params = Keyword.get(opts, :params, %{})
    theme = Keyword.get(opts, :theme, :light)
    selected_widget = Keyword.get(opts, :selected_widget_id)

    default_viewport =
      case selected_widget do
        nil -> @default_viewport
        _ -> @widget_viewport
      end

    viewport = Keyword.get(opts, :viewport, default_viewport)

    with {:ok, source} <- dashboard_source(dashboard),
         {:ok, timeframe} <- resolve_timeframe(source, dashboard, params),
         {:ok, export} <- fetch_series(source, timeframe),
         {:ok, layout} <-
           compose_layout(dashboard, export, timeframe, theme, viewport, selected_widget) do
      {:ok, layout}
    end
  end

  @doc """
  Builds a layout for the dashboard ID by fetching the record.
  """
  @spec build_from_id(String.t(), opts()) :: {:ok, Layout.t()} | {:error, term()}
  def build_from_id(dashboard_id, opts \\ []) do
    dashboard = Organizations.get_dashboard!(dashboard_id)
    do_build(dashboard, opts)
  rescue
    e in Ecto.NoResultsError -> {:error, e}
  end

  @doc """
  Builds a layout for a specific widget by fetching the dashboard record.
  """
  @spec build_widget_from_id(String.t(), String.t(), opts()) ::
          {:ok, Layout.t()} | {:error, term()}
  def build_widget_from_id(dashboard_id, widget_id, opts \\ []) do
    dashboard = Organizations.get_dashboard!(dashboard_id)
    build_widget(dashboard, widget_id, opts)
  rescue
    e in Ecto.NoResultsError -> {:error, e}
  end

  defp dashboard_source(%{source_type: "project", source_id: id}) do
    {:ok, Organizations.get_project!(id) |> Source.from_project()}
  rescue
    e in Ecto.NoResultsError -> {:error, e}
  end

  defp dashboard_source(%{source_id: id}) do
    {:ok, Organizations.get_database!(id) |> Source.from_database()}
  rescue
    e in Ecto.NoResultsError -> {:error, e}
  end

  defp resolve_timeframe(source, dashboard, params) do
    config = Source.stats_config(source)
    available_granularities = Source.available_granularities(source)

    defaults = %{
      default_timeframe: dashboard.default_timeframe || Source.default_timeframe(source) || "24h",
      default_granularity:
        dashboard.default_granularity || Source.default_granularity(source) || "1h"
    }

    {from, to, granularity, smart, use_fixed} =
      UrlParsing.parse_url_params(params, config, available_granularities, defaults)

    {:ok,
     %{
       from: from,
       to: to,
       granularity: granularity,
       smart: smart,
       use_fixed: use_fixed,
       key: resolved_key(dashboard, params),
       display: TimeframeParsing.format_timeframe_display(from, to),
       params: params
     }}
  end

  defp fetch_series(source, %{from: from, to: to, granularity: granularity, key: key}) do
    SeriesExport.fetch(
      source,
      key,
      from,
      to,
      granularity,
      progress_callback: nil
    )
  end

  defp resolved_key(dashboard, params) do
    case Map.get(params, "key") do
      key when is_binary(key) and key != "" -> key
      _ -> dashboard.key || ""
    end
  end

  defp compose_layout(dashboard, export, timeframe, theme, viewport, selected_widget_id) do
    stats_struct = export.raw.series

    datasets_raw = WidgetData.datasets_from_dashboard(stats_struct, dashboard)
    dataset_maps = WidgetData.dataset_maps(datasets_raw)
    all_grid_items = WidgetView.grid_items(dashboard)
    filtered_grid = maybe_filter_widgets(all_grid_items, selected_widget_id)

    cond do
      filtered_grid == [] and selected_widget_id ->
        {:error, :widget_not_found}

      filtered_grid == [] ->
        {:error, :no_widgets}

      true ->
        pruned_datasets =
          maybe_prune_dataset_maps(dataset_maps, Enum.map(filtered_grid, &widget_id/1))

        render_assigns = %{
          dashboard: %{
            dashboard
            | payload: Map.put(dashboard.payload || %{}, "grid", filtered_grid)
          },
          stats: stats_struct,
          print_mode: true,
          current_user: nil,
          can_edit_dashboard: false,
          can_clone_dashboard: false,
          can_manage_dashboard: false,
          can_manage_lock: false,
          is_public_access: true,
          public_token: nil,
          kpi_values: pruned_datasets.kpi_values,
          kpi_visuals: pruned_datasets.kpi_visuals,
          timeseries: pruned_datasets.timeseries,
          category: pruned_datasets.category,
          table: pruned_datasets.table,
          text_widgets: pruned_datasets.text,
          list: pruned_datasets.list,
          distribution: pruned_datasets.distribution,
          export_params: %{},
          dashboard_id: dashboard.id,
          print_width: printable_width(viewport),
          print_cell_height:
            widget_print_cell_height(filtered_grid, selected_widget_id, viewport),
          transponder_info: %{}
        }

        Layout.new(%{
          id: dashboard.id,
          kind: if(selected_widget_id, do: :dashboard_widget, else: :dashboard),
          title: dashboard.name,
          theme: theme,
          viewport: viewport,
          assigns: %{theme_class: theme_class(theme)}
        })
        |> Layout.put_meta(:timeframe, %{
          from: timeframe.from,
          to: timeframe.to,
          granularity: timeframe.granularity,
          smart: timeframe.smart,
          use_fixed: timeframe.use_fixed,
          display: timeframe.display
        })
        |> Layout.put_meta(:key, timeframe.key)
        |> maybe_put_widget_meta(selected_widget_id)
        |> Layout.with_render(WidgetView, :grid, render_assigns)
        |> then(&{:ok, &1})
    end
  end

  defp theme_class(:dark), do: "dark"
  defp theme_class(_), do: nil

  defp maybe_filter_widgets(items, nil), do: items

  defp maybe_filter_widgets(items, widget_id) do
    items
    |> Enum.filter(fn item -> widget_id(item) == widget_id end)
    |> normalize_single_widget_layout()
  end

  defp maybe_prune_dataset_maps(datasets, widget_ids) do
    Map.new(datasets, fn {key, map} ->
      pruned =
        map
        |> Enum.filter(fn {id, _} -> id in widget_ids end)
        |> Enum.into(%{})

      {key, pruned}
    end)
  end

  defp printable_width(%{width: width}) when is_integer(width) and width > 0 do
    min(width, 1366)
  end

  defp printable_width(_), do: 1366

  defp widget_print_cell_height(_grid, nil, _viewport), do: nil

  defp widget_print_cell_height(grid, _widget_id, %{height: height})
       when is_list(grid) and is_integer(height) and height > 0 do
    rows =
      grid
      |> Enum.map(&derive_widget_height/1)
      |> Enum.max(fn -> 0 end)

    cond do
      rows <= 0 -> nil
      true -> max(div(height, rows), 40)
    end
  end

  defp widget_print_cell_height(_, _, _), do: nil

  defp widget_id(%{"id" => id}), do: to_string(id)
  defp widget_id(%{id: id}), do: to_string(id)
  defp widget_id(_), do: nil

  defp maybe_put_widget_meta(layout, nil), do: layout

  defp maybe_put_widget_meta(layout, widget_id),
    do: Layout.put_meta(layout, :widget, %{id: widget_id})

  defp normalize_single_widget_layout([item]) do
    item =
      item
      |> ensure_string_keys()
      |> Map.put("x", 0)
      |> Map.put("y", 0)
      |> Map.put("w", 12)

    base_height = derive_widget_height(item)
    enforced_height = max(base_height, 12)

    item =
      item
      |> Map.put("h", enforced_height)
      |> expand_tab_children(enforced_height)

    [item]
  end

  defp normalize_single_widget_layout(items), do: items

  defp ensure_string_keys(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      string_key =
        cond do
          is_binary(key) -> key
          is_atom(key) -> Atom.to_string(key)
          true -> to_string(key)
        end

      normalized_value =
        cond do
          is_map(value) -> ensure_string_keys(value)
          is_list(value) -> Enum.map(value, &ensure_string_keys/1)
          true -> value
        end

      Map.put(acc, string_key, normalized_value)
    end)
  end

  defp ensure_string_keys(other), do: other

  defp derive_widget_height(%{"h" => height}) when is_integer(height) and height > 0, do: height

  defp derive_widget_height(%{"tabs" => %{"widgets" => widgets}}) when is_list(widgets) do
    widgets
    |> Enum.map(&derive_widget_height/1)
    |> Enum.max(fn -> 6 end)
  end

  defp derive_widget_height(_), do: 6

  defp expand_tab_children(%{"tabs" => %{"widgets" => widgets} = tabs} = widget, height) do
    expanded_widgets =
      widgets
      |> Enum.map(&ensure_string_keys/1)
      |> Enum.map(fn child ->
        child
        |> Map.put("x", 0)
        |> Map.put("y", 0)
        |> Map.put("w", 12)
        |> Map.put("h", height)
        |> expand_tab_children(height)
      end)

    updated_tabs = Map.put(tabs, "widgets", expanded_widgets)

    widget
    |> Map.put("tabs", updated_tabs)
    |> Map.put("h", height)
  end

  defp expand_tab_children(widget, _height), do: widget
end
