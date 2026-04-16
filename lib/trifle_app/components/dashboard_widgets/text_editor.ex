defmodule TrifleApp.Components.DashboardWidgets.TextEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.{Helpers, SeriesColorSelector}

  attr :widget, :map, required: true

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})

    subtype = Helpers.normalize_text_subtype(Map.get(widget, "subtype"))
    background_selector = Helpers.text_widget_background_selector_for_form(widget)

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:subtype, subtype)
      |> assign(:background_selector, background_selector)
      |> assign(:title_size, Helpers.normalize_text_title_size(Map.get(widget, "title_size")))
      |> assign(:alignment, Helpers.normalize_text_alignment(Map.get(widget, "alignment")))

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
        <SeriesColorSelector.input
          id_prefix={"text-background-color-#{Map.get(@widget, "id", "new")}"}
          name="text_background_color_selector"
          index={0}
          indexed_name={false}
          selector={@background_selector}
          allow_palette_rotate={false}
          default_label="Default"
          default_preview_colors={[Helpers.default_text_widget_background_preview()]}
          class="mt-2 sm:max-w-xs"
        />
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
