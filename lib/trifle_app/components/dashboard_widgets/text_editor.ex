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
        <input type="hidden" name="text_subtype" value={@subtype} />
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
          <%= for {label, value, position} <- text_subtype_options() do %>
            <button
              type="button"
              class={text_toggle_classes(@subtype == value, position)}
              phx-click="change_text_subtype"
              phx-value-widget-id={Map.get(@widget, "id")}
              phx-value-text-subtype={value}
            >
              {label}
            </button>
          <% end %>
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
            name="text_payload"
            rows="10"
            class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm font-mono"
            placeholder="<p>Write custom HTML here</p>"
          ><%= Map.get(@widget, "payload", "") %></textarea>
          <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Content is sanitized—only safe HTML is rendered.
          </p>
        </div>
      <% else %>
        <div class="sm:col-span-2">
          <p class="text-xs text-gray-500 dark:text-slate-400">
            This widget uses the main title field above as its headline.
          </p>
        </div>
      <% end %>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Title Size
        </label>
        <input type="hidden" name="text_title_size" value={@title_size} />
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
          <%= for {label, value, position} <- text_title_size_options() do %>
            <button
              type="button"
              class={text_toggle_classes(@title_size == value, position)}
              phx-click="set_text_title_size"
              phx-value-widget-id={Map.get(@widget, "id")}
              phx-value-text-title-size={value}
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Alignment
        </label>
        <input type="hidden" name="text_alignment" value={@alignment} />
        <div class="inline-flex rounded-md shadow-sm border border-gray-200 dark:border-slate-600 overflow-hidden mt-2">
          <%= for {label, value, position} <- text_alignment_options() do %>
            <button
              type="button"
              class={text_toggle_classes(@alignment == value, position)}
              phx-click="set_text_alignment"
              phx-value-widget-id={Map.get(@widget, "id")}
              phx-value-text-alignment={value}
            >
              {label}
            </button>
          <% end %>
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

  defp text_subtype_options do
    [
      {"Header", "header", :first},
      {"HTML", "html", :last}
    ]
  end

  defp text_title_size_options do
    [
      {"L", "large", :first},
      {"M", "medium", :middle},
      {"S", "small", :last}
    ]
  end

  defp text_alignment_options do
    [
      {"Left", "left", :first},
      {"Center", "center", :middle},
      {"Right", "right", :last}
    ]
  end

  defp text_toggle_classes(selected, position) do
    base =
      "px-4 py-1.5 text-sm font-medium focus:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 transition min-w-[3.5rem] text-center"

    corners =
      case position do
        :first -> "rounded-l-md"
        :last -> "rounded-r-md"
        _ -> "border-x border-gray-200 dark:border-slate-600"
      end

    state =
      if selected do
        "bg-teal-600 text-white hover:bg-teal-500"
      else
        "bg-white text-gray-700 hover:bg-gray-50 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
      end

    Enum.join([base, corners, state], " ")
  end
end
