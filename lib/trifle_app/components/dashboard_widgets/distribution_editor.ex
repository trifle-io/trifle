defmodule TrifleApp.Components.DashboardWidgets.DistributionEditor do
  @moduledoc false

  use Phoenix.Component

  alias TrifleApp.Components.DashboardWidgets.Helpers
  alias TrifleApp.Components.DashboardWidgets.MetricSeriesEditor
  alias TrifleApp.Components.DashboardWidgets.SeriesDisplayEditor

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    widget_type = widget |> Map.get("type", "distribution") |> to_string() |> String.downcase()
    is_heatmap = widget_type == "heatmap"

    mode =
      if is_heatmap do
        "3d"
      else
        Helpers.normalize_distribution_mode(Map.get(widget, "mode"))
      end

    designator_forms = Helpers.distribution_designators_for_form(widget)
    path_aggregation = Helpers.distribution_path_aggregation_for_form(widget)
    heatmap_color_mode = Helpers.heatmap_color_mode_for_form(widget)
    heatmap_color_config = Helpers.heatmap_color_config_for_form(widget)
    heatmap_palettes = Helpers.heatmap_palette_options()

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:mode, mode)
      |> assign(:is_heatmap, is_heatmap)
      |> assign(:designator_forms, designator_forms)
      |> assign(:path_aggregation, path_aggregation)
      |> assign(:heatmap_color_mode, heatmap_color_mode)
      |> assign(:heatmap_color_config, heatmap_color_config)
      |> assign(:heatmap_palettes, heatmap_palettes)
      |> assign(:legend?, Map.get(widget, "legend", true))

    ~H"""
    <div class="space-y-6">
      <MetricSeriesEditor.editor
        widget={@widget}
        path_options={@path_options}
        path_placeholder="metrics.distribution.*"
        path_help="Path rows can target wildcard bucket groups. Expression rows apply bucket-by-bucket after matching bindings and compatible bucket layouts."
      />

      <SeriesDisplayEditor.controls widget={@widget} />

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Chart Mode
          </label>
          <%= if @is_heatmap do %>
            <input type="hidden" name="dist_mode" value="3d" />
            <div class="mt-2 rounded-md border border-gray-300 bg-gray-50 px-3 py-2 text-sm text-gray-700 dark:border-slate-600 dark:bg-slate-700 dark:text-slate-100">
              Heatmap
            </div>
          <% else %>
            <select
              name="dist_mode"
              class="mt-2 block w-full rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
            >
              <option value="2d" selected={@mode == "2d"}>2D Bar</option>
              <option value="3d" selected={@mode == "3d"}>3D Scatter</option>
            </select>
          <% end %>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Legend
          </label>
          <div class="mt-2 flex items-center gap-2">
            <input type="hidden" name="dist_legend" value="false" />
            <input
              type="checkbox"
              id="dist-legend"
              name="dist_legend"
              value="true"
              checked={@legend?}
              class="h-4 w-4 rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:bg-slate-700 dark:border-slate-600"
            />
            <label for="dist-legend" class="text-sm text-gray-700 dark:text-slate-300">
              Show legend
            </label>
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Path Aggregation
          </label>
          <select
            name="dist_path_aggregation"
            class="mt-2 block w-full rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          >
            <option value="none" selected={@path_aggregation == "none"}>
              None (separate series)
            </option>
            <option value="sum" selected={@path_aggregation == "sum"}>Sum</option>
            <option value="mean" selected={@path_aggregation == "mean"}>Average</option>
            <option value="max" selected={@path_aggregation == "max"}>Max</option>
            <option value="min" selected={@path_aggregation == "min"}>Min</option>
          </select>
        </div>
      </div>

      <%= if @is_heatmap do %>
        <div class="space-y-4 rounded-lg border border-slate-200 bg-white px-4 py-3 shadow-sm dark:border-slate-700 dark:bg-slate-800">
          <div class="space-y-0.5">
            <p class="text-sm font-medium text-gray-900 dark:text-white">Heatmap Color Scale</p>
            <p class="text-xs text-gray-500 dark:text-slate-400">
              Auto mode uses path color selection. Single mode uses transparent to full selected color.
            </p>
          </div>

          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
              Color Mode
            </label>
            <select
              name="dist_heatmap_color_mode"
              class="mt-2 block w-full rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
            >
              <option value="auto" selected={@heatmap_color_mode == "auto"}>Auto</option>
              <option value="single" selected={@heatmap_color_mode == "single"}>Single color</option>
              <option value="palette" selected={@heatmap_color_mode == "palette"}>
                Palette gradient
              </option>
              <option value="diverging" selected={@heatmap_color_mode == "diverging"}>
                Diverging
              </option>
            </select>
          </div>

          <%= if @heatmap_color_mode == "single" do %>
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                Base Color
              </label>
              <input
                type="color"
                name="dist_heatmap_single_color"
                value={@heatmap_color_config["single_color"]}
                class="mt-1 h-10 w-16 rounded-md border border-gray-300 bg-white p-1 dark:border-slate-600 dark:bg-slate-700"
              />
            </div>
          <% end %>

          <%= if @heatmap_color_mode == "palette" do %>
            <div class="space-y-2">
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                Palette
              </label>
              <select
                name="dist_heatmap_palette_id"
                class="mt-1 block w-full rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
              >
                <%= for palette <- @heatmap_palettes do %>
                  <option
                    value={palette.id}
                    selected={@heatmap_color_config["palette_id"] == palette.id}
                  >
                    {palette.label}
                  </option>
                <% end %>
              </select>
            </div>
          <% end %>

          <%= if @heatmap_color_mode == "diverging" do %>
            <div class="space-y-3">
              <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
                <div>
                  <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                    Negative Color
                  </label>
                  <input
                    type="color"
                    name="dist_heatmap_negative_color"
                    value={@heatmap_color_config["negative_color"]}
                    class="mt-1 h-10 w-16 rounded-md border border-gray-300 bg-white p-1 dark:border-slate-600 dark:bg-slate-700"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                    Positive Color
                  </label>
                  <input
                    type="color"
                    name="dist_heatmap_positive_color"
                    value={@heatmap_color_config["positive_color"]}
                    class="mt-1 h-10 w-16 rounded-md border border-gray-300 bg-white p-1 dark:border-slate-600 dark:bg-slate-700"
                  />
                </div>
              </div>

              <div class="flex items-center gap-2">
                <input type="hidden" name="dist_heatmap_symmetric" value="false" />
                <input
                  type="checkbox"
                  id="dist-heatmap-symmetric"
                  name="dist_heatmap_symmetric"
                  value="true"
                  checked={@heatmap_color_config["symmetric"]}
                  class="h-4 w-4 rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:bg-slate-700 dark:border-slate-600"
                />
                <label for="dist-heatmap-symmetric" class="text-sm text-gray-700 dark:text-slate-300">
                  Symmetric around zero
                </label>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                  Center Value
                </label>
                <input
                  type="number"
                  step="any"
                  name="dist_heatmap_center_value"
                  value={@heatmap_color_config["center_value"]}
                  disabled={@heatmap_color_config["symmetric"]}
                  class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 disabled:cursor-not-allowed disabled:opacity-70 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                />
              </div>
            </div>
          <% end %>
        </div>
      <% end %>

      <.designator_section
        title="Horizontal Designator"
        prefix="dist_designator"
        form={@designator_forms.horizontal}
        note="X-axis buckets for 2D bars, 3D scatter, and heatmap views."
      />

      <%= if @mode == "3d" do %>
        <.designator_section
          title="Vertical Designator"
          prefix="dist_v_designator"
          form={@designator_forms.vertical}
          note="Y-axis buckets for 3D scatter and heatmap views."
        />
      <% end %>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :prefix, :string, required: true
  attr :form, :map, required: true
  attr :note, :string, default: nil
  attr :disabled, :boolean, default: false

  defp designator_section(assigns) do
    assigns =
      assigns
      |> assign_new(:note, fn -> nil end)
      |> assign_new(:disabled, fn -> false end)
      |> assign(:selected_type, assigns.form.type || "custom")

    ~H"""
    <div class="space-y-4 rounded-lg border border-slate-200 bg-white px-4 py-3 shadow-sm dark:border-slate-700 dark:bg-slate-800">
      <div class="flex items-center justify-between gap-3">
        <div class="space-y-0.5">
          <p class="text-sm font-medium text-gray-900 dark:text-white">
            {@title}
          </p>
          <p :if={@note} class="text-xs text-gray-500 dark:text-slate-400">
            {@note}
          </p>
        </div>
        <span
          :if={@disabled}
          class="text-[11px] rounded-full bg-slate-100 px-2 py-1 font-medium text-slate-700 dark:bg-slate-700 dark:text-slate-200"
        >
          3D only
        </span>
      </div>

      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
          Designator Type
        </label>
        <select
          name={"#{@prefix}_type"}
          class="mt-2 block w-full rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          data-role="distribution-designator-type"
          disabled={@disabled}
        >
          <option value="custom" selected={@selected_type == "custom"}>Custom buckets</option>
          <option value="linear" selected={@selected_type == "linear"}>Linear</option>
          <option value="geometric" selected={@selected_type == "geometric"}>Geometric</option>
        </select>
      </div>

      <div
        class="space-y-4"
        data-role="distribution-designator-fields"
        data-selected-type={@selected_type}
        data-axis={@prefix}
      >
        <div data-type="custom" class={designator_field_class(@selected_type == "custom")}>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Custom Buckets
          </label>
          <textarea
            name={"#{@prefix}_buckets"}
            rows="3"
            class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
            placeholder="10, 20, 30"
            disabled={@disabled || @selected_type != "custom"}
          ><%= @form.buckets_text %></textarea>
          <p class="text-xs text-gray-500 dark:text-slate-400 mt-1">
            Enter comma or newline separated bucket boundaries in ascending order.
          </p>
        </div>

        <div data-type="linear" class={designator_field_class(@selected_type == "linear")}>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Linear Settings
          </label>
          <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
            <div>
              <label class="text-xs text-gray-500 dark:text-slate-400">Min</label>
              <input
                type="number"
                step="any"
                name={"#{@prefix}_min"}
                value={@form.min}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                disabled={@disabled || @selected_type != "linear"}
              />
            </div>
            <div>
              <label class="text-xs text-gray-500 dark:text-slate-400">Max</label>
              <input
                type="number"
                step="any"
                name={"#{@prefix}_max"}
                value={@form.max}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                disabled={@disabled || @selected_type != "linear"}
              />
            </div>
            <div>
              <label class="text-xs text-gray-500 dark:text-slate-400">Step</label>
              <input
                type="number"
                step="any"
                name={"#{@prefix}_step"}
                value={@form.step}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                disabled={@disabled || @selected_type != "linear"}
              />
            </div>
          </div>
        </div>

        <div data-type="geometric" class={designator_field_class(@selected_type == "geometric")}>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
            Geometric Settings
          </label>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label class="text-xs text-gray-500 dark:text-slate-400">Min</label>
              <input
                type="number"
                step="any"
                name={"#{@prefix}_min"}
                value={@form.min}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                disabled={@disabled || @selected_type != "geometric"}
              />
            </div>
            <div>
              <label class="text-xs text-gray-500 dark:text-slate-400">Max</label>
              <input
                type="number"
                step="any"
                name={"#{@prefix}_max"}
                value={@form.max}
                class="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                disabled={@disabled || @selected_type != "geometric"}
              />
            </div>
          </div>
          <p class="text-xs text-gray-500 dark:text-slate-400 mt-1">
            Values outside the provided range will be grouped automatically.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp designator_field_class(true) do
    "space-y-2"
  end

  defp designator_field_class(false) do
    "space-y-2 hidden"
  end
end
