defmodule TrifleApp.ExploreV2Live do
  @moduledoc """
  GridStack-backed Explore surface that reuses the existing Explore data pipeline.
  """
  use TrifleApp, :live_view

  alias Decimal
  alias Jason
  alias TrifleApp.Components.DataTable

  alias TrifleApp.Components.DashboardWidgets.WidgetView

  alias TrifleApp.DesignSystem.ChartColors
  alias TrifleApp.ExploreLive

  import TrifleApp.Components.DashboardFooter, only: [dashboard_footer: 1]

  @activity_widget_id "explore-activity"
  @table_widget_id "explore-table"
  @list_widget_id "explore-keys-list"

  @impl true
  def mount(params, session, socket) do
    params
    |> ExploreLive.mount(session, socket)
    |> ensure_v2_path()
  end

  defp ensure_v2_path({:ok, socket}) do
    {:ok, assign(socket, :explore_path, explore_v2_path())}
  end

  defp ensure_v2_path({:ok, socket, opts}) do
    {:ok, assign(socket, :explore_path, explore_v2_path()), opts}
  end

  @impl true
  def handle_params(params, url, socket) do
    ExploreLive.handle_params(params, url, socket)
  end

  @impl true
  def handle_event("expand_widget", %{"id" => id}, socket) do
    widget = find_explore_widget(socket, id)
    expanded = build_explore_expanded_widget(socket, widget)

    {:noreply, assign(socket, :expanded_widget, expanded)}
  end

  def handle_event("close_expanded_widget", _params, socket) do
    {:noreply, assign(socket, :expanded_widget, nil)}
  end

  def handle_event(event, params, socket), do: ExploreLive.handle_event(event, params, socket)

  @impl true
  def handle_async(task, result, socket) do
    ExploreLive.handle_async(task, result, socket)
  end

  @impl true
  def handle_info(msg, socket) do
    ExploreLive.handle_info(msg, socket)
  end

  @impl true
  def render(assigns) do
    summary = ExploreLive.get_summary_stats(assigns)
    dashboard = build_dashboard(assigns)
    timeseries_map = build_timeseries_dataset(assigns)
    table_map = build_table_dataset(assigns)
    list_map = build_list_dataset(assigns)

    assigns =
      assigns
      |> assign(:summary, summary)
      |> assign(:dashboard_config, dashboard)
      |> assign(:timeseries_map, timeseries_map)
      |> assign(:table_map, table_map)
      |> assign(:list_map, list_map)
      |> assign(:widget_export_config, %{type: :dashboard})

    ~H"""
    <%= if @no_source do %>
      <div
        id="explore-v2-root"
        class="flex flex-col dark:bg-slate-900 min-h-screen relative"
        phx-hook="FileDownload"
      >
        <div class="max-w-3xl mx-auto mt-16">
          <div class="bg-white dark:bg-slate-800 rounded-lg shadow p-6">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-2">
              No sources found
            </h2>
            <p class="text-gray-600 dark:text-slate-300">
              Please add a database or project first to use Explore.
            </p>
            <div class="mt-4">
              <.link
                navigate={~p"/dbs"}
                class="inline-flex items-center px-3 py-2 bg-teal-600 text-white rounded-md hover:bg-teal-700"
              >
                Go to Databases
              </.link>
            </div>
          </div>
        </div>
      </div>
    <% else %>
      <div
        id="explore-v2-root"
        class="flex flex-col dark:bg-slate-900 min-h-screen relative"
        phx-hook="FileDownload"
      >
        <iframe
          name="download_iframe"
          style="display:none"
          aria-hidden="true"
          onload="window.__resetDownloadMenus && window.__resetDownloadMenus(); window.dispatchEvent(new CustomEvent('download:complete'))"
        >
        </iframe>
        <script>
          window.__resetDownloadMenus = window.__resetDownloadMenus || function(){
            try {
              var menus = document.querySelectorAll('[data-download-menu],[data-widget-download-menu]');
              menus.forEach(function(menu){
                var button = menu.querySelector('[data-role=download-button]');
                var label = menu.querySelector('[data-role=download-text]');
                var icon = menu.querySelector('[data-role=download-icon]');
                var spinner = menu.querySelector('[data-role=download-spinner]');
                var defaultLabel = (menu.dataset && menu.dataset.defaultLabel) || 'Download';
                if (button) {
                  button.disabled = false;
                  button.classList.remove('opacity-70','cursor-wait');
                  button.removeAttribute('aria-busy');
                  button.removeAttribute('data-loading');
                }
                if (icon) icon.classList.remove('hidden');
                if (spinner) spinner.classList.add('hidden');
                if (label && defaultLabel) {
                  label.textContent = defaultLabel;
                }
              });
            } catch (_) {}
          };
          window.__downloadPoller = window.__downloadPoller || setInterval(function(){
            try {
              var m = document.cookie.match(/(?:^|; )download_token=([^;]+)/);
              if (m) {
                document.cookie = 'download_token=; Max-Age=0; path=/';
                if (window.__resetDownloadMenus) window.__resetDownloadMenus();
                window.dispatchEvent(new CustomEvent('download:complete'));
              }
            } catch (e) {}
          }, 500);
        </script>

        <%= if (@loading_chunks && @loading_progress) || @transponding do %>
          <div class="absolute inset-0 bg-white bg-opacity-75 dark:bg-slate-900 dark:bg-opacity-90 z-50">
            <div class="absolute left-1/2 -translate-x-1/2" style="top: 33%;">
              <div class="flex flex-col items-center space-y-3">
                <div class="flex items-center space-x-2">
                  <div class="animate-spin rounded-full h-6 w-6 border-2 border-gray-300 dark:border-slate-600 border-t-teal-500">
                  </div>
                  <span class="text-sm text-gray-600 dark:text-white">
                    <%= if @transponding do %>
                      Transponding data...
                    <% else %>
                      Scientificating piece {@loading_progress.current} of {@loading_progress.total}...
                    <% end %>
                  </span>
                </div>
                <div class="w-64 h-2">
                  <%= if @loading_chunks && @loading_progress do %>
                    <div class="w-full bg-gray-200 dark:bg-slate-600 rounded-full h-2">
                      <div
                        class="bg-teal-500 h-2 rounded-full transition-all duration-300"
                        style={"width: #{Float.round(@loading_progress.current / @loading_progress.total * 100, 2)}%"}
                      >
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>

        <.live_component
          module={TrifleApp.Components.FilterBar}
          id="explore-v2-filter-bar"
          config={@database_config}
          granularity={@granularity}
          available_granularities={@available_granularities}
          from={@from}
          to={@to}
          smart_timeframe_input={@smart_timeframe_input}
          use_fixed_display={@use_fixed_display}
          show_timeframe_dropdown={@show_timeframe_dropdown}
          show_granularity_dropdown={@show_granularity_dropdown}
          show_controls={true}
          sources={@sources}
          selected_source={@selected_source_ref}
          force_granularity_dropdown={false}
        />

        <div class="mt-6">
          <WidgetView.grid
            dashboard={@dashboard_config}
            stats={nil}
            current_user={@current_user}
            can_edit_dashboard={false}
            is_public_access={false}
            public_token={nil}
            kpi_values={%{}}
            kpi_visuals={%{}}
            timeseries={@timeseries_map}
            category={%{}}
            table={@table_map}
            text_widgets={%{}}
            list={@list_map}
            export_params={%{}}
            widget_export={@widget_export_config}
            transponder_info={@transponder_info}
          />
        </div>

        <%= if @expanded_widget do %>
          <.app_modal
            id="explore-expanded-widget"
            show={true}
            size="full"
            on_cancel={JS.push("close_expanded_widget")}
          >
            <:title>
              <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
                <div class="flex items-center gap-3">
                  <span>{@expanded_widget.title}</span>
                  <span class="inline-flex items-center rounded-full bg-teal-100/70 dark:bg-teal-900/40 px-3 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200">
                    {String.capitalize(@expanded_widget.type || "widget")}
                  </span>
                </div>
              </div>
            </:title>
            <:body>
              <%= case @expanded_widget.type do %>
                <% "table" -> %>
                  <% render_table =
                    Map.get(@table_map || %{}, @expanded_widget.widget_id) %>
                  <div class="h-[80vh] flex flex-col gap-6 overflow-y-auto">
                    <div class="flex-1 min-h-[500px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                      <%= if render_table do %>
                        <DataTable.table
                          dataset={render_table}
                          transponder_info={@transponder_info || %{}}
                          outer_class="flex-1 flex flex-col min-h-0"
                        />
                      <% else %>
                        <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                          Configure this widget with a path to display table data.
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% "list" -> %>
                  <% list_data = Map.get(@list_map || %{}, @expanded_widget.widget_id) %>
                  <% list_items = expanded_list_items(list_data) %>
                  <% empty_message = expanded_list_empty_message(list_data) %>
                  <div class="h-[80vh] flex flex-col gap-6 overflow-y-auto">
                    <div class="flex-1 min-h-[400px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                      <%= if list_items == [] do %>
                        <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center">
                          {empty_message}
                        </div>
                      <% else %>
                        <div class="h-full w-full overflow-auto">
                          <table class="min-w-full divide-y divide-gray-200 dark:divide-slate-700 text-sm">
                            <tbody class="divide-y divide-gray-100 dark:divide-slate-800 text-gray-900 dark:text-slate-100">
                              <%= for item <- list_items do %>
                                <% color = expanded_list_color(item) %>
                                <% label = expanded_list_label(item) %>
                                <% value = expanded_list_value(item) %>
                                <% badge_bg = expanded_list_color_with_alpha(color, "15") %>
                                <% badge_border = expanded_list_color_with_alpha(color, "40") %>
                                <tr>
                                  <td class="px-4 py-3 align-middle">
                                    <div class="flex items-center gap-3 min-w-0">
                                      <span
                                        class="inline-flex h-2.5 w-2.5 rounded-full flex-shrink-0"
                                        style={"background-color: #{color}"}
                                        aria-hidden="true"
                                      >
                                      </span>
                                      <div class="min-w-0">
                                        <p
                                          class="font-mono text-xs truncate text-slate-700 dark:text-slate-200"
                                          title={label}
                                        >
                                          {label}
                                        </p>
                                        <%= if path = expanded_list_path(item) do %>
                                          <p
                                            class="text-[11px] text-slate-500 dark:text-slate-400 truncate"
                                            title={path}
                                          >
                                            {path}
                                          </p>
                                        <% end %>
                                      </div>
                                    </div>
                                  </td>
                                  <td class="px-4 py-3 text-right align-middle">
                                    <span
                                      class="inline-flex items-center rounded-md border px-3 py-1 text-xs font-semibold"
                                      style={
                                        "border-color: #{badge_border}; background-color: #{badge_bg}; color: #{color}"
                                      }
                                    >
                                      {value}
                                    </span>
                                  </td>
                                </tr>
                              <% end %>
                            </tbody>
                          </table>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% _ -> %>
                  <% chart_payload =
                    Map.get(@timeseries_map || %{}, @expanded_widget.widget_id) %>
                  <% chart_data = encode_optional_json(chart_payload) %>
                  <div
                    id={"expanded-widget-#{@expanded_widget.widget_id}"}
                    class="h-[80vh] flex flex-col gap-6 overflow-y-auto"
                    phx-hook="ExpandedWidgetView"
                    data-type={@expanded_widget.type}
                    data-title={@expanded_widget.title}
                    data-colors={ChartColors.json_palette()}
                    data-chart={chart_data}
                    data-visual={nil}
                    data-text={nil}
                  >
                    <div class="flex-1 min-h-[500px]">
                      <div class="h-full w-full rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/40 p-4">
                        <div data-role="chart" class="h-full w-full"></div>
                      </div>
                    </div>
                    <div class="flex-1 min-h-[300px] rounded-lg border border-gray-200/80 dark:border-slate-700/60 bg-white dark:bg-slate-900/60 overflow-auto">
                      <div data-role="table-root" class="h-full w-full overflow-auto"></div>
                    </div>
                  </div>
              <% end %>
            </:body>
          </.app_modal>
        <% end %>

        <%= if @summary do %>
          <.dashboard_footer
            class="mt-8"
            summary={@summary}
            load_duration_microseconds={@load_duration_microseconds}
            show_export_dropdown={@show_export_dropdown}
            dashboard={@dashboard_config}
            export_params={%{}}
            download_menu_id="explore-download-menu"
          >
            <:export_menu>
              <button
                type="button"
                phx-click="download_explore_csv"
                class="w-full text-left px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
              >
                <svg
                  class="h-4 w-4 mr-2 text-teal-600 dark:text-teal-400"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                  />
                </svg>
                CSV (table)
              </button>
              <button
                type="button"
                phx-click="download_explore_json"
                class="w-full text-left px-3 py-2 text-xs text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-700 flex items-center"
              >
                <svg
                  class="h-4 w-4 mr-2 text-indigo-600 dark:text-indigo-400"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 16.5m0 0L7.5 12m4.5 4.5V3"
                  />
                </svg>
                JSON (raw)
              </button>
            </:export_menu>
          </.dashboard_footer>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp build_dashboard(assigns) do
    %{
      id: "explore-v2",
      key: assigns[:key],
      name: "Explore",
      payload: %{"grid" => grid_widgets(assigns)}
    }
  end

  defp grid_widgets(assigns) do
    [
      activity_widget(assigns),
      list_widget(),
      table_widget()
    ]
  end

  defp activity_widget(assigns) do
    %{
      "id" => @activity_widget_id,
      "type" => "timeseries",
      "title" => activity_title(assigns),
      "chart_type" => "bar",
      "legend" => false,
      "stacked" => stacked_chart?(assigns),
      "normalized" => false,
      "paths" => timeline_paths(assigns),
      "y_label" => "Events",
      "w" => 12,
      "h" => 3,
      "x" => 0,
      "y" => 0
    }
  end

  defp table_widget do
    %{
      "id" => @table_widget_id,
      "type" => "table",
      "title" => "Explore",
      "w" => 12,
      "h" => 8,
      "x" => 0,
      "y" => 7
    }
  end

  defp list_widget do
    %{
      "id" => @list_widget_id,
      "type" => "list",
      "title" => "Keys",
      "path" => "keys",
      "sort" => "alpha",
      "w" => 12,
      "h" => 4,
      "x" => 0,
      "y" => 3
    }
  end

  defp activity_title(%{key: key}) when is_binary(key) and key != "" do
    "Activity · #{key}"
  end

  defp activity_title(_assigns), do: "Activity"

  defp stacked_chart?(%{chart_type: "single"}), do: false
  defp stacked_chart?(_assigns), do: true

  defp timeline_paths(%{chart_type: "single", key: key}) when is_binary(key) and key != "" do
    ["keys.#{key}"]
  end

  defp timeline_paths(_assigns), do: ["keys.*"]

  defp build_timeseries_dataset(%{timeline: timeline, chart_type: chart_type} = assigns) do
    series =
      timeline
      |> decode_timeline_series(chart_type, assigns[:key])
      |> apply_selected_series_color(chart_type, assigns[:selected_key_color])

    %{
      @activity_widget_id => %{
        id: @activity_widget_id,
        chart_type: "bar",
        stacked: stacked_chart?(assigns),
        normalized: false,
        legend: false,
        y_label: "Events",
        series: series
      }
    }
  end

  defp apply_selected_series_color(series, "single", color)
       when is_binary(color) and color != "" do
    Enum.map(series, fn item -> Map.put(item, :color, color) end)
  end

  defp apply_selected_series_color(series, _chart_type, _color), do: series

  defp build_table_dataset(%{stats: nil}), do: %{}

  defp build_table_dataset(assigns) do
    dataset =
      assigns.stats
      |> DataTable.from_stats(
        granularity: assigns.granularity,
        empty_message: "No data available yet.",
        id: @table_widget_id
      )
      |> Map.put(:mode, "aggrid")

    %{@table_widget_id => dataset}
  end

  defp build_list_dataset(assigns) do
    keys_map = assigns.keys || %{}

    items =
      keys_map
      |> Enum.sort_by(fn {key, _} -> key end)
      |> Enum.map(fn {key, value} ->
        numeric_value = normalize_value(value)

        %{
          path: "keys.#{key}",
          label: key,
          value: numeric_value,
          formatted_value: ExploreLive.format_number(numeric_value),
          color: ExploreLive.get_key_color(keys_map, key)
        }
      end)
      |> Enum.reject(fn %{value: value} -> (value || 0) == 0 end)

    selected_key =
      case assigns[:key] do
        key when is_binary(key) and key != "" -> key
        _ -> nil
      end

    selected_path =
      case selected_key do
        nil -> nil
        key -> "keys.#{key}"
      end

    %{
      @list_widget_id => %{
        id: @list_widget_id,
        path: "keys",
        sort: "alpha",
        items: items,
        empty_message: "No keys tracked for this timeframe.",
        selected_key: selected_key,
        selected_path: selected_path,
        select_event: "select_key",
        deselect_event: "deselect_key"
      }
    }
  end

  defp find_explore_widget(socket, id) do
    socket.assigns
    |> grid_widgets()
    |> Enum.find(fn widget -> to_string(widget["id"]) == to_string(id) end)
  end

  defp build_explore_expanded_widget(_socket, nil), do: nil

  defp build_explore_expanded_widget(_socket, widget) do
    id = widget |> Map.get("id") |> to_string()
    type = explore_widget_type(widget)
    title = widget |> Map.get("title", "") |> to_string() |> String.trim()

    %{
      widget_id: id,
      title: if(title == "", do: "Untitled Widget", else: title),
      type: type
    }
  end

  defp explore_widget_type(widget) do
    widget
    |> Map.get("type", "kpi")
    |> to_string()
    |> String.downcase()
  end

  defp decode_timeline_series(nil, _chart_type, _key), do: []
  defp decode_timeline_series("", _chart_type, _key), do: []

  defp decode_timeline_series(timeline_json, "single", key) do
    name = key || "Activity"
    data = timeline_points(timeline_json)
    [%{name: name, data: data}]
  end

  defp decode_timeline_series(timeline_json, _chart_type, _key) do
    case decode_json(timeline_json) do
      list when is_list(list) ->
        Enum.map(list, fn
          %{"name" => series_name, "data" => data} ->
            %{name: series_name, data: normalize_points(data)}

          %{name: series_name, data: data} ->
            %{name: series_name, data: normalize_points(data)}

          other when is_map(other) ->
            name = Map.get(other, "name") || Map.get(other, :name) || "Series"
            data = Map.get(other, "data") || Map.get(other, :data) || []
            %{name: name, data: normalize_points(data)}

          _ ->
            %{name: "Series", data: []}
        end)

      _ ->
        []
    end
  end

  defp timeline_points(timeline_json) do
    case decode_json(timeline_json) do
      list when is_list(list) ->
        Enum.map(list, fn
          [ts, value] -> [ts, value]
          {ts, value} -> [ts, value]
          other -> other
        end)

      _ ->
        []
    end
  end

  defp decode_json(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, data} -> data
      _ -> []
    end
  end

  defp decode_json(value), do: value

  defp normalize_points(points) when is_list(points) do
    Enum.map(points, fn
      [ts, value] -> [ts, value]
      {ts, value} -> [ts, value]
      other -> List.wrap(other)
    end)
  end

  defp normalize_points(_), do: []

  defp normalize_value(%Decimal{} = value), do: Decimal.to_float(value)
  defp normalize_value(value) when is_number(value), do: value * 1.0
  defp normalize_value(_), do: 0.0

  defp encode_optional_json(nil), do: nil

  defp encode_optional_json(data) do
    Jason.encode!(data)
  rescue
    _ -> nil
  end

  defp expanded_list_items(%{items: items}) when is_list(items), do: items
  defp expanded_list_items(%{"items" => items}) when is_list(items), do: items
  defp expanded_list_items(_), do: []

  defp expanded_list_empty_message(%{empty_message: msg}) when is_binary(msg) and msg != "",
    do: msg

  defp expanded_list_empty_message(%{"empty_message" => msg}) when is_binary(msg) and msg != "",
    do: msg

  defp expanded_list_empty_message(_), do: "No data available yet."

  defp expanded_list_color(item) do
    Map.get(item, :color) ||
      Map.get(item, "color") ||
      ChartColors.primary()
  end

  defp expanded_list_label(item) do
    Map.get(item, :label) || Map.get(item, "label") || expanded_list_path(item) || "Item"
  end

  defp expanded_list_value(item) do
    Map.get(item, :formatted_value) ||
      Map.get(item, "formatted_value") ||
      Map.get(item, :value) ||
      Map.get(item, "value") ||
      "0"
  end

  defp expanded_list_path(item) do
    Map.get(item, :path) || Map.get(item, "path")
  end

  defp expanded_list_color_with_alpha(color, suffix) do
    cond do
      is_binary(color) and String.starts_with?(color, "#") ->
        color <> suffix

      true ->
        color
    end
  end

  defp explore_v2_path, do: ~p"/explore/v2"
end
