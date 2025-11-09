defmodule TrifleApp.ProjectSettingsLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Project
  alias TrifleApp.ProjectsLive

  @week_options [
    {"Monday", 1},
    {"Tuesday", 2},
    {"Wednesday", 3},
    {"Thursday", 4},
    {"Friday", 5},
    {"Saturday", 6},
    {"Sunday", 7}
  ]

  @impl true
  def mount(%{"id" => id}, _session, %{assigns: %{current_user: user}} = socket) do
    project = Organizations.get_project!(id)

    if project.user_id == user.id do
      {:ok,
       socket
       |> assign(:project, project)
       |> assign(:page_title, "Projects · #{project.name} · Settings")
       |> assign(:nav_section, :projects)
       |> assign(:breadcrumb_links, project_breadcrumb_links(project, "Settings"))
       |> assign(:form, to_form(Organizations.change_project(project)))
       |> assign(:show_edit_modal, false)
       |> assign(:time_zones, time_zones())
       |> assign(:week_options, @week_options)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You do not have access to that project.")
       |> redirect(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_event("open_edit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:form, to_form(Organizations.change_project(socket.assigns.project)))
     |> assign(:show_edit_modal, true)}
  end

  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    case Organizations.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project updated successfully.")
         |> assign(:project, project)
         |> assign(:page_title, "Projects · #{project.name} · Settings")
         |> assign(:nav_section, :projects)
         |> assign(:breadcrumb_links, project_breadcrumb_links(project, "Settings"))
         |> assign(:form, to_form(Organizations.change_project(project)))
         |> assign(:show_edit_modal, false)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="sm:p-4">
        <.project_nav project={@project} current={:settings} />
      </div>

      <div class="space-y-6 px-4 pb-6 sm:px-6 lg:px-8">
        <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg dark:bg-slate-800">
          <div class="px-4 py-6 sm:px-6">
            <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
                  Project overview
                </h2>
                <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
                  Key attributes that describe how this project is configured.
                </p>
              </div>
              <button
                type="button"
                phx-click="open_edit_modal"
                class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
              >
                Edit project
              </button>
            </div>
          </div>
          <div class="border-t border-gray-100 dark:border-slate-700">
            <dl class="divide-y divide-gray-100 dark:divide-slate-700">
              <.detail_row label="Project name">
                {@project.name}
              </.detail_row>
              <.detail_row label="Project ID">
                <span class="font-mono text-sm text-gray-700 dark:text-slate-200 break-all">
                  {@project.id}
                </span>
              </.detail_row>
              <.detail_row label="Time zone">
                {@project.time_zone}
              </.detail_row>
              <.detail_row label="Beginning of week">
                {format_week_start(@project)}
              </.detail_row>
              <.detail_row label="Created">
                {format_timestamp(@project.inserted_at)}
              </.detail_row>
              <.detail_row label="Last updated">
                {format_timestamp(@project.updated_at)}
              </.detail_row>
            </dl>
          </div>
        </div>

        <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg dark:bg-slate-800">
          <div class="px-4 py-6 sm:px-6">
            <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
              Reporting defaults
            </h2>
            <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
              Settings applied when dashboards or Explore load without explicit overrides.
            </p>
          </div>
          <div class="border-t border-gray-100 dark:border-slate-700">
            <dl class="divide-y divide-gray-100 dark:divide-slate-700">
              <.detail_row label="Granularities">
                <%= if @project.granularities && @project.granularities != [] do %>
                  <div class="flex flex-wrap gap-2">
                    <%= for granularity <- @project.granularities do %>
                      <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                        {granularity}
                      </span>
                    <% end %>
                  </div>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">
                    Using defaults (1s, 1m, 1h, 1d, 1w, 1mo, 1q, 1y)
                  </span>
                <% end %>
              </.detail_row>
              <.detail_row label="Default timeframe">
                <%= if present?(@project.default_timeframe) do %>
                  <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                    {@project.default_timeframe}
                  </span>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
                <% end %>
              </.detail_row>
              <.detail_row label="Default granularity">
                <%= if present?(@project.default_granularity) do %>
                  <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                    {@project.default_granularity}
                  </span>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
                <% end %>
              </.detail_row>
              <.detail_row label="Data retention">
                {format_expire_after(@project.expire_after)}
              </.detail_row>
            </dl>
          </div>
        </div>
      </div>
    </div>

    <.app_modal
      :if={@show_edit_modal}
      id="project-edit-modal"
      show
      on_cancel={JS.push("close_edit_modal")}
    >
      <:title>Edit Project</:title>
      <:body>
        <.form_container for={@form} phx-submit="save" class="space-y-6">
          <:header
            title="Project details"
            subtitle="Update the defaults that shape how dashboards, Explore, and ingestion behave."
          />

          <.form_field field={@form[:name]} label="Project name" required />

          <.form_field
            field={@form[:time_zone]}
            type="select"
            label="Time zone"
            options={@time_zones}
            prompt="Select a time zone"
            required
          />

          <.form_field
            field={@form[:beginning_of_week]}
            type="select"
            label="Beginning of week"
            options={@week_options}
            required
          />

          <div class="space-y-2">
            <label
              for={@form[:granularities].id}
              class="block text-sm font-medium text-gray-900 dark:text-white"
            >
              Granularities
            </label>
            <input
              id={@form[:granularities].id}
              name={@form[:granularities].name}
              type="text"
              value={granularities_to_string(@form[:granularities].value)}
              placeholder="1m, 1h, 1d, 1w, 1mo"
              required
              class="block w-full rounded-lg border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
            />
            <p class="text-xs text-gray-600 dark:text-gray-400">
              Comma-separated list matching the granularities you want available in Explore and dashboards.
            </p>
            <.form_errors field={@form[:granularities]} />
          </div>

          <.form_field
            field={@form[:default_timeframe]}
            label="Default timeframe"
            placeholder="7d"
            help_text="Optional. Applied when dashboards or Explore load without explicit overrides."
          />

          <.form_field
            field={@form[:default_granularity]}
            label="Default granularity"
            placeholder="1h"
            help_text="Optional. Should match one of the configured granularities."
          />

          <.form_field
            field={@form[:expire_after]}
            type="number"
            label="Expire after (seconds)"
            placeholder="86400"
            help_text="Optional. Leave blank to keep metrics forever."
          />

          <:actions>
            <.form_actions>
              <.secondary_button type="button" phx-click="close_edit_modal">
                Cancel
              </.secondary_button>
              <.primary_button phx-disable-with="Saving...">Save changes</.primary_button>
            </.form_actions>
          </:actions>
        </.form_container>
      </:body>
    </.app_modal>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="px-4 py-6 sm:grid sm:grid-cols-3 sm:gap-4 sm:px-6">
      <dt class="text-sm font-medium text-gray-900 dark:text-white">{@label}</dt>
      <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  defp time_zones do
    ProjectsLive.time_zones()
  end

  defp granularities_to_string(nil), do: ""

  defp granularities_to_string(value) when is_list(value) do
    value
    |> Enum.join(", ")
  end

  defp granularities_to_string(value) when is_binary(value), do: value
  defp granularities_to_string(_), do: ""

  defp project_breadcrumb_links(%Project{} = project, last) do
    project_name = project.name || "Project"

    [
      {"Projects", ~p"/projects"},
      {project_name, ~p"/projects/#{project.id}/transponders"},
      last
    ]
  end

  defp present?(value) when value in [nil, ""], do: false
  defp present?(_), do: true

  defp format_week_start(%Project{} = project) do
    project
    |> Project.beginning_of_week_for()
    |> case do
      nil -> "Monday"
      atom when is_atom(atom) -> atom |> Atom.to_string() |> String.capitalize()
      value -> to_string(value)
    end
  end

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(%NaiveDateTime{} = timestamp) do
    Calendar.strftime(timestamp, "%B %d, %Y at %I:%M %p")
  end

  defp format_expire_after(nil), do: "Keep metrics forever"
  defp format_expire_after(0), do: "Keep metrics forever"

  defp format_expire_after(seconds) when is_integer(seconds) and seconds > 0 do
    cond do
      rem(seconds, 86_400) == 0 ->
        days = div(seconds, 86_400)
        pluralize(days, "day")

      rem(seconds, 3_600) == 0 ->
        hours = div(seconds, 3_600)
        pluralize(hours, "hour")

      rem(seconds, 60) == 0 ->
        minutes = div(seconds, 60)
        pluralize(minutes, "minute")

      true ->
        pluralize(seconds, "second")
    end
  end

  defp format_expire_after(value) when is_binary(value) do
    value
    |> Integer.parse()
    |> case do
      {int, ""} -> format_expire_after(int)
      _ -> "Keep metrics forever"
    end
  end

  defp format_expire_after(_), do: "Keep metrics forever"

  defp pluralize(value, unit) when value == 1, do: "1 #{unit}"
  defp pluralize(value, unit), do: "#{value} #{unit}s"
end
