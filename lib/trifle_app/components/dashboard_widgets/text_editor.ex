defmodule TrifleApp.Components.DashboardWidgets.TextEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.Helpers

  attr :widget, :map, required: true

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    subtype = Helpers.normalize_text_subtype(Map.get(widget, "subtype"))
    color_id = Helpers.normalize_text_color_id(Map.get(widget, "color"))

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:subtype, subtype)
      |> assign(:color_id, color_id)
      |> assign(:selected_color, Helpers.resolve_text_widget_color(color_id))
      |> assign(:title_size, Helpers.normalize_text_title_size(Map.get(widget, "title_size")))
      |> assign(:alignment, Helpers.normalize_text_alignment(Map.get(widget, "alignment")))
      |> assign(:colors, Helpers.text_widget_colors())

    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Content Type
        </label>
        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
          <select
            name="text_subtype"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
            phx-change="change_text_subtype"
            phx-value-widget-id={Map.get(@widget, "id")}
          >
            <option value="header" selected={@subtype == "header"}>Header</option>
            <option value="html" selected={@subtype == "html"}>HTML</option>
          </select>
          <svg
            viewBox="0 0 16 16"
            fill="currentColor"
            data-slot="icon"
            aria-hidden="true"
            class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
          >
            <path
              d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
              clip-rule="evenodd"
              fill-rule="evenodd"
            />
          </svg>
        </div>
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Background color
        </label>
        <div x-data="{ open: false }" class="relative mt-2 sm:max-w-xs" x-cloak>
          <input type="hidden" name="text_color" value={@color_id} />
          <button
            type="button"
            class="w-full h-10 cursor-default rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 py-2 pl-3 pr-10 text-left text-sm font-medium text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500"
            x-on:click="open = !open"
            x-bind:aria-expanded="open"
            aria-haspopup="listbox"
          >
            <div class="flex items-center justify-between">
              <span>{@selected_color.label}</span>
              <span class="inline-flex items-center gap-2">
                <span
                  class="inline-block h-5 w-5 rounded-md border border-white/80 shadow-sm"
                  style={"background-color: #{@selected_color.background};"}
                  aria-hidden="true"
                >
                </span>
              </span>
            </div>
            <span class="pointer-events-none absolute inset-y-0 right-0 flex items-center pr-2">
              <svg class="h-5 w-5 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 9l-7 7-7-7"
                />
              </svg>
            </span>
          </button>

          <div
            x-show="open"
            x-on:click.away="open = false"
            class="absolute z-50 mt-1 w-full max-h-60 overflow-auto rounded-md bg-white dark:bg-slate-800 py-1 text-base shadow-lg ring-1 ring-black ring-opacity-5 focus:outline-none sm:text-sm"
            role="listbox"
          >
            <%= for color <- @colors do %>
              <button
                type="button"
                phx-click="change_text_color"
                phx-value-widget-id={Map.get(@widget, "id")}
                phx-value-color={color.id}
                x-on:click="open = false"
                class={[
                  "w-full text-left px-3 py-2 hover:bg-gray-100 dark:hover:bg-slate-600 cursor-pointer",
                  if(@color_id == color.id, do: "bg-gray-100 dark:bg-slate-700")
                ]}
                role="option"
                aria-selected={@color_id == color.id}
              >
                <div class="flex items-center justify-between">
                  <span class="text-sm text-gray-900 dark:text-white">{color.label}</span>
                  <span class="inline-flex items-center">
                    <span
                      class="inline-block h-5 w-5 rounded-md border border-white/80 shadow-sm"
                      style={"background-color: #{color.background};"}
                      aria-hidden="true"
                    >
                    </span>
                  </span>
                </div>
              </button>
            <% end %>
          </div>
        </div>
      </div>

      <%= if @subtype == "html" do %>
        <div class="sm:col-span-2">
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            HTML Content
          </label>
          <textarea
            name="text_html_content"
            rows="10"
            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm font-mono"
            placeholder="<p>Write custom HTML here</p>"
          ><%= Map.get(@widget, "payload", "") %></textarea>
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Content is sanitized—only safe HTML is rendered.
          </p>
        </div>
      <% else %>
        <div class="sm:col-span-2 space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
              Headline
            </label>
            <input
              type="text"
              name="text_title"
              value={Map.get(@widget, "title", "")}
              class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
              placeholder="e.g., Enter product ID"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
              Default value
            </label>
            <input
              type="text"
              name="text_default_value"
              value={Map.get(@widget, "default_value", "")}
              class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
              placeholder="Leave blank for no default"
            />
          </div>
        </div>
      <% end %>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Title Size
        </label>
        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
          <select
            name="text_title_size"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
          >
            <option value="large" selected={@title_size == "large"}>Large</option>
            <option value="medium" selected={@title_size == "medium"}>Medium</option>
            <option value="small" selected={@title_size == "small"}>Small</option>
          </select>
          <svg
            viewBox="0 0 16 16"
            fill="currentColor"
            data-slot="icon"
            aria-hidden="true"
            class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
          >
            <path
              d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
              clip-rule="evenodd"
              fill-rule="evenodd"
            />
          </svg>
        </div>
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Alignment
        </label>
        <div class="grid grid-cols-1 sm:max-w-xs mt-2">
          <select
            name="text_alignment"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 bg-white dark:bg-slate-800 text-gray-900 dark:text-white outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm/6"
          >
            <option value="left" selected={@alignment == "left"}>Left</option>
            <option value="center" selected={@alignment == "center"}>Center</option>
            <option value="right" selected={@alignment == "right"}>Right</option>
          </select>
          <svg
            viewBox="0 0 16 16"
            fill="currentColor"
            data-slot="icon"
            aria-hidden="true"
            class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 dark:text-slate-400 sm:h-4 sm:w-4"
          >
            <path
              d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
              clip-rule="evenodd"
              fill-rule="evenodd"
            />
          </svg>
        </div>
      </div>

      <div class="sm:col-span-2">
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Subtitle
        </label>
        <textarea
          name="text_subtitle"
          rows="3"
          class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          placeholder="Optional supporting text"
        ><%= Map.get(@widget, "subtitle", "") %></textarea>
      </div>
    </div>
    """
  end
end
