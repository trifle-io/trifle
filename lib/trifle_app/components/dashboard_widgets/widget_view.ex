defmodule TrifleApp.Components.DashboardWidgets.WidgetView do
  @moduledoc false

  use TrifleApp, :html

  alias TrifleApp.Components.DashboardWidgets.Text, as: TextWidgets
  alias TrifleApp.Components.DashboardWidgets.WidgetDataBridge
  alias TrifleApp.DesignSystem.ChartColors

  attr :dashboard, :map, required: true
  attr :stats, :any, default: nil
  attr :print_mode, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :can_edit_dashboard, :boolean, default: false
  attr :is_public_access, :boolean, default: false
  attr :public_token, :string, default: nil

  def grid(assigns) do
    assigns =
      assigns
      |> assign_new(:grid_items, fn ->
        grid_items(assigns.dashboard)
      end)

    assigns = assign(assigns, :has_grid_items, assigns.grid_items != [])

    assigns =
      assigns
      |> assign_new(:text_items, fn -> text_items(assigns.grid_items) end)

    ~H"""
    <div class={[
      "mb-6",
      if(@has_grid_items, do: nil, else: "hidden")
    ]}>
      <div
        id="dashboard-grid"
        class="grid-stack"
        phx-update="ignore"
        phx-hook="DashboardGrid"
        data-print-mode={if @print_mode, do: "true", else: "false"}
        data-editable={
          if !@is_public_access && @current_user && @can_edit_dashboard,
            do: "true",
            else: "false"
        }
        data-cols="12"
        data-min-rows="8"
        data-add-btn-id={"dashboard-" <> @dashboard.id <> "-add-widget"}
        data-colors={ChartColors.json_palette()}
        data-initial-grid={Jason.encode!(@grid_items)}
        data-initial-text={Jason.encode!(@text_items)}
        data-dashboard-id={@dashboard.id}
        data-public-token={@public_token}
      >
      </div>
    </div>

    <div class="hidden" aria-hidden="true">
      <%= for widget <- @grid_items do %>
        <.live_component
          module={WidgetDataBridge}
          id={"widget-data-#{widget["id"]}"}
          widget={widget}
          stats={@stats}
        />
      <% end %>
    </div>
    """
  end

  attr :widget, :map, required: true
  attr :editable, :boolean, default: false

  def grid_item(assigns) do
    assigns =
      assigns
      |> assign(:widget_id, widget_id(assigns.widget))
      |> assign(:grid, grid_position(assigns.widget))
      |> assign(:title, widget_title(assigns.widget))

    ~H"""
    <div
      class="grid-stack-item"
      gs-w={@grid.w}
      gs-h={@grid.h}
      gs-x={@grid.x}
      gs-y={@grid.y}
      gs-id={@widget_id}
    >
      <div class="grid-stack-item-content bg-white dark:bg-slate-800 border border-gray-200 dark:border-slate-700 rounded-md shadow p-3 text-gray-700 dark:text-slate-300 flex flex-col group">
        <div class="grid-widget-header flex items-center justify-between mb-2 pb-1 border-b border-gray-100 dark:border-slate-700/60">
          <div class="grid-widget-handle cursor-move flex-1 flex items-center gap-2 py-1 min-w-0">
            <div class="grid-widget-title font-semibold truncate text-gray-900 dark:text-white">
              <%= @title %>
            </div>
          </div>
          <div class="grid-widget-actions flex items-center gap-1 opacity-0 transition-opacity duration-150 group-hover:opacity-100 group-focus-within:opacity-100">
            <button
              type="button"
              class="grid-widget-expand inline-flex items-center p-1 rounded group"
              data-widget-id={@widget_id}
              title="Expand widget"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
                />
              </svg>
            </button>
            <%= if @editable do %>
              <button
                type="button"
                class="grid-widget-edit inline-flex items-center p-1 rounded group"
                data-widget-id={@widget_id}
                title="Edit widget"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4 text-gray-600 dark:text-slate-300 transition-colors group-hover:text-gray-800 dark:group-hover:text-slate-100"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z"
                  />
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                  />
                </svg>
              </button>
            <% end %>
          </div>
        </div>
        <div class="grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400">
          Chart is coming soon
        </div>
      </div>
    </div>
    """
  end

  defp widget_id(widget) do
    widget
    |> Map.get("id") || widget |> Map.get(:id) || widget |> Map.get("uuid") || widget |> Map.get(:uuid)
    |> to_string()
  end

  defp grid_position(widget) do
    %{
      w: widget |> Map.get("w") || widget |> Map.get(:w) || 3,
      h: widget |> Map.get("h") || widget |> Map.get(:h) || 2,
      x: widget |> Map.get("x") || widget |> Map.get(:x) || 0,
      y: widget |> Map.get("y") || widget |> Map.get(:y) || 0
    }
    |> Enum.into(%{}, fn {k, value} -> {k, to_string(value)} end)
  end

  defp widget_title(widget) do
    widget["title"] || widget[:title] || default_title(widget)
  end

  defp default_title(widget) do
    widget_id = widget_id(widget)
    prefix = "Widget "

    suffix =
      widget_id
      |> String.slice(0, 6)
      |> case do
        nil -> "—"
        slice -> slice
      end

    prefix <> suffix
  end

  def grid_items(dashboard) do
    dashboard
    |> Map.get(:payload, %{})
    |> Map.get("grid", [])
    |> normalize_items()
  end

  def text_items(grid_items), do: TextWidgets.widgets(grid_items)

  defp normalize_items(items) when is_list(items), do: items
  defp normalize_items(_other), do: []
end
