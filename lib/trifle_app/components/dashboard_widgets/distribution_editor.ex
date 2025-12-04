defmodule TrifleApp.Components.DashboardWidgets.DistributionEditor do
  @moduledoc false

  use Phoenix.Component

  import TrifleApp.Components.PathInput, only: [path_autocomplete_input: 1]

  alias TrifleApp.Components.DashboardWidgets.Helpers

  attr :widget, :map, required: true
  attr :path_options, :list, default: []

  def editor(assigns) do
    widget = Map.get(assigns, :widget, %{})
    paths = Helpers.distribution_paths_for_form(widget)
    mode = Helpers.normalize_distribution_mode(Map.get(widget, "mode"))
    designator_forms = Helpers.distribution_designators_for_form(widget)

    assigns =
      assigns
      |> assign(:widget, widget)
      |> assign(:paths, paths)
      |> assign(:mode, mode)
      |> assign(:designator_forms, designator_forms)
      |> assign(:legend?, Map.get(widget, "legend", true))

    ~H"""
    <div class="space-y-6">
      <div>
        <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-2">
          Metric Paths
        </label>
        <div
          id={"widget-#{Map.get(@widget, "id")}-distribution-paths"}
          phx-hook="CategoryPaths"
          data-widget-id={Map.get(@widget, "id")}
          data-event-name="distribution_paths_update"
          data-path-input-name="dist_paths[]"
          class="space-y-3"
        >
          <div class="space-y-2">
            <%= for {path, index} <- Enum.with_index(@paths) do %>
              <div class="flex items-center gap-2">
                <div class="flex-1 min-w-0">
                  <.path_autocomplete_input
                    id={"widget-dist-path-#{Map.get(@widget, "id")}-#{index}"}
                    name="dist_paths[]"
                    value={path}
                    placeholder="metrics.distribution.*"
                    path_options={@path_options}
                    input_class="block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
                  />
                </div>
                <button
                  type="button"
                  data-action="remove"
                  data-index={index}
                  class="inline-flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-md bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:cursor-not-allowed disabled:opacity-50 dark:bg-slate-700 dark:text-slate-200 dark:hover:bg-slate-600"
                  aria-label="Remove path"
                  disabled={length(@paths) == 1}
                >
                  &minus;
                </button>
              </div>
            <% end %>
          </div>
          <button
            type="button"
            data-action="add"
            class="inline-flex items-center gap-1 rounded-md bg-teal-500 px-3 py-2 text-sm font-medium text-white hover:bg-teal-600 dark:bg-teal-600 dark:hover:bg-teal-500"
          >
            <span aria-hidden="true">+</span>
            <span class="sr-only">Add path</span>
          </button>
          <p class="text-xs text-gray-500 dark:text-slate-400">
            Use <code>*</code>
            to include nested buckets (for example <code>metrics.distribution.*</code>).
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
            Chart Mode
          </label>
          <select
            name="dist_mode"
            class="mt-2 block w-full rounded-md border-gray-300 py-2 pl-3 pr-10 text-base focus:border-teal-500 focus:outline-none focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white sm:text-sm"
          >
            <option value="2d" selected={@mode == "2d"}>2D Bar</option>
            <option value="3d" selected={@mode == "3d"}>3D Scatter</option>
          </select>
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
      </div>

      <.designator_section
        title="Horizontal Designator"
        prefix="dist_designator"
        form={@designator_forms.horizontal}
        note="X-axis buckets for both 2D and 3D distributions."
      />

      <%= if @mode == "3d" do %>
        <.designator_section
          title="Vertical Designator"
          prefix="dist_v_designator"
          form={@designator_forms.vertical}
          note="Y-axis buckets for 3D distributions."
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
