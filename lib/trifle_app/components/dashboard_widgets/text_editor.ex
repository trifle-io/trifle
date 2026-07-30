defmodule TrifleApp.Components.DashboardWidgets.TextEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.DesignSystem.ButtonGroup

  alias TrifleApp.Components.DashboardWidgets.{EditorIcons, Helpers, SeriesColorSelector}

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
    <div class="grid grid-cols-1 gap-4 xl:grid-cols-3">
      <div class="space-y-4 xl:col-span-2">
        <%= if @subtype == "html" do %>
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
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
        <% end %>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
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

      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Content Type
          </label>
          <input type="hidden" name="text_subtype" value={@subtype} />
          <.button_group size="sm">
            <:button
              :for={{label, value} <- text_subtype_options()}
              phx-click="change_text_subtype"
              values={%{"widget-id" => Map.get(@widget, "id"), "text-subtype" => value}}
              selected={@subtype == value}
              label={label}
            />
          </.button_group>
          <p :if={@subtype != "html"} class="mt-2 text-xs text-gray-500 dark:text-slate-400">
            Uses the main title field above as its headline.
          </p>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
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
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Title Size
          </label>
          <input type="hidden" name="text_title_size" value={@title_size} />
          <.button_group size="sm">
            <:button
              :for={{label, value, help} <- text_title_size_options()}
              phx-click="set_text_title_size"
              values={%{"widget-id" => Map.get(@widget, "id"), "text-title-size" => value}}
              selected={@title_size == value}
              label={label}
              tooltip={help}
            />
          </.button_group>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Alignment
          </label>
          <input type="hidden" name="text_alignment" value={@alignment} />
          <.button_group size="sm" labels="hidden">
            <:button
              :for={{label, value} <- text_alignment_options()}
              phx-click="set_text_alignment"
              values={%{"widget-id" => Map.get(@widget, "id"), "text-alignment" => value}}
              selected={@alignment == value}
              label={label}
            >
              <.alignment_icon alignment={value} />
            </:button>
          </.button_group>
        </div>
      </div>
    </div>
    """
  end

  defp text_subtype_options do
    [
      {"Header", "header"},
      {"HTML", "html"}
    ]
  end

  defp text_title_size_options do
    [
      {"L", "large", "Large"},
      {"M", "medium", "Medium"},
      {"S", "small", "Small"}
    ]
  end

  defp text_alignment_options do
    [
      {"Left", "left"},
      {"Center", "center"},
      {"Right", "right"}
    ]
  end

  attr :alignment, :string, required: true

  defp alignment_icon(%{alignment: "left"} = assigns), do: ~H"<EditorIcons.align_left_icon />"
  defp alignment_icon(%{alignment: "center"} = assigns), do: ~H"<EditorIcons.align_center_icon />"
  defp alignment_icon(%{alignment: "right"} = assigns), do: ~H"<EditorIcons.align_right_icon />"
end
