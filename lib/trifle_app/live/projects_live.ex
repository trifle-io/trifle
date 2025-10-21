defmodule TrifleApp.ProjectsLive do
  use TrifleApp, :live_view

  alias Phoenix.LiveView.JS
  alias Trifle.Organizations
  alias Trifle.Organizations.Project

  @week_options [
    {"Monday", 1},
    {"Tuesday", 2},
    {"Wednesday", 3},
    {"Thursday", 4},
    {"Friday", 5},
    {"Saturday", 6},
    {"Sunday", 7}
  ]

  @accent_classes ~w(bg-teal-500 bg-sky-500 bg-violet-500 bg-amber-500 bg-rose-500 bg-emerald-500)

  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
            Your Projects
          </h1>
          <p class="mt-2 text-sm text-gray-700 dark:text-gray-300">
            Pick a Project to configure Transponders, Access Tokens and other Settings.
          </p>
        </div>
        <div class="flex gap-2">
          <.link
            patch={~p"/projects/new"}
            aria-label="New Project"
            class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
          >
            <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
            </svg>
            <span class="hidden md:inline">New Project</span>
          </.link>
        </div>
      </div>

      <%= if Enum.empty?(@projects) do %>
        <div class="rounded-lg border border-dashed border-slate-400/60 bg-white dark:bg-slate-800 p-8 text-center">
          <svg
            class="mx-auto h-12 w-12 text-gray-400 dark:text-gray-500"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="1.5"
              d="M3 7.5A2.25 2.25 0 015.25 5.25h3.6a2.25 2.25 0 001.59-.66l1.32-1.32a2.25 2.25 0 011.59-.66h4.45A2.25 2.25 0 0120.5 4.86v12.39A2.25 2.25 0 0118.25 19.5H5.25A2.25 2.25 0 013 17.25V7.5z"
            />
          </svg>
          <h3 class="mt-2 text-sm font-semibold text-gray-900 dark:text-white">No projects yet</h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">
            Create your first project to start collecting metrics and sharing dashboards.
          </p>
          <div class="mt-4">
            <.link
              patch={~p"/projects/new"}
              class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
            >
              New Project
            </.link>
          </div>
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for project <- @projects do %>
            <div
              class="group flex items-center justify-between rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 hover:bg-gray-50 dark:hover:bg-slate-700/40 transition-colors cursor-pointer"
              phx-click={JS.navigate(~p"/projects/#{project.id}")}
            >
              <div class="flex items-center gap-3 pl-3 py-3">
                <div class={"h-10 w-1.5 rounded " <> project_accent_class(project)}></div>
                <div>
                  <div class="flex items-center gap-2">
                    <div class="inline-flex h-8 min-w-[2rem] items-center justify-center rounded-md bg-gray-100 px-1 text-sm font-semibold text-gray-700 dark:bg-slate-700 dark:text-white">
                      {project_initials(project)}
                    </div>
                    <div class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400">
                      {project.name}
                    </div>
                  </div>
                  <% meta = project_list_meta(project) %>
                  <%= if meta != [] do %>
                    <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                      <%= for {item, idx} <- Enum.with_index(meta) do %>
                        <%= if idx > 0 do %>
                          <span class="text-gray-300 dark:text-slate-500">•</span>
                        <% end %>
                        <span>{item}</span>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
              <div class="flex items-center gap-3 pr-3">
                <button
                  type="button"
                  class="hidden rounded-md border border-gray-200 dark:border-slate-600 px-2 py-1 text-xs font-medium text-gray-600 dark:text-slate-300 hover:border-teal-400 hover:text-teal-600 dark:hover:border-teal-400 dark:hover:text-teal-300 sm:inline-flex"
                  phx-click="open_settings"
                  phx-value-id={project.id}
                >
                  Settings
                </button>
                <svg
                  class="h-4 w-4 text-gray-400 group-hover:text-teal-500 dark:text-gray-500 dark:group-hover:text-teal-400"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3"
                  />
                </svg>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>

    <.app_modal id="new-project-modal" show={@show_new_modal} on_cancel="close_new_modal">
      <:title>New Project</:title>
      <:body>
        <.form_container for={@form} phx-submit="create" class="space-y-6">
          <:header
            title="Project details"
            subtitle="Name the project and choose defaults for reports and dashboards."
          />

          <.form_field
            field={@form[:name]}
            label="Project name"
            placeholder="Secret weather station"
            required
          />

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
            field={@form[:expire_after]}
            type="number"
            label="Expire after (seconds)"
            placeholder="86400"
            help_text="Optional. Leave blank to keep metrics forever."
          />

          <:actions>
            <.form_actions>
              <.primary_button phx-disable-with="Creating...">Create project</.primary_button>
              <.secondary_button patch={~p"/projects"}>Cancel</.secondary_button>
            </.form_actions>
          </:actions>
        </.form_container>
      </:body>
    </.app_modal>
    """
  end

  def mount(params, _session, socket) do
    projects = Organizations.list_users_projects(socket.assigns.current_user)
    changeset = Organizations.change_project(%Project{})

    socket =
      socket
      |> assign(:projects, projects)
      |> assign(:form, to_form(changeset))
      |> assign(:time_zones, time_zones())
      |> assign(:week_options, @week_options)
      |> assign(:page_title, "Projects")
      |> assign(:show_new_modal, false)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Projects · New")
    |> assign(:show_new_modal, true)
    |> assign(:form, to_form(Organizations.change_project(%Project{})))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Projects")
    |> assign(:show_new_modal, false)
    |> assign(:projects, Organizations.list_users_projects(socket.assigns.current_user))
  end

  defp apply_action(socket, _action, _params), do: socket

  def time_zones do
    now = DateTime.utc_now()

    Tzdata.zone_list()
    |> Enum.map(fn zone ->
      tzinfo = Timex.Timezone.get(zone, now)
      offset = Timex.TimezoneInfo.format_offset(tzinfo)
      label = "#{tzinfo.full_name} - #{tzinfo.abbreviation} (#{offset})"

      {label, tzinfo.full_name}
    end)
    |> Enum.uniq()
  end

  def handle_event("create", %{"project" => project_params}, socket) do
    case Organizations.create_users_project(project_params, socket.assigns.current_user) do
      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:ok, project} ->
        socket =
          socket
          |> put_flash(:info, "#{project.name} created")
          |> assign(:projects, Organizations.list_users_projects(socket.assigns.current_user))
          |> assign(:form, to_form(Organizations.change_project(%Project{})))
          |> assign(:show_new_modal, false)

        {:noreply, push_patch(socket, to: ~p"/projects")}
    end
  end

  def handle_event("open_settings", %{"id" => project_id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/projects/#{project_id}/settings")}
  end

  def handle_event("close_new_modal", _params, socket) do
    {:noreply, push_patch(assign(socket, :show_new_modal, false), to: ~p"/projects")}
  end

  defp week_label(1), do: "Monday"
  defp week_label(2), do: "Tuesday"
  defp week_label(3), do: "Wednesday"
  defp week_label(4), do: "Thursday"
  defp week_label(5), do: "Friday"
  defp week_label(6), do: "Saturday"
  defp week_label(7), do: "Sunday"
  defp week_label(_), do: "Monday"

  defp project_initials(%Project{name: name}) when is_binary(name) do
    trimmed = String.trim(name)

    trimmed
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
    |> String.slice(0, 3)
    |> String.upcase()
    |> case do
      "" -> "PR"
      initials -> initials
    end
  end

  defp project_initials(_), do: "PR"

  defp project_accent_class(%Project{} = project) do
    hash_input = project.id || project.name || "project"
    idx = :erlang.phash2(hash_input, length(@accent_classes))
    Enum.at(@accent_classes, idx - 1)
  end

  defp granularities_to_string(nil), do: ""

  defp granularities_to_string(value) when is_list(value) do
    value
    |> Enum.join(", ")
  end

  defp granularities_to_string(value) when is_binary(value), do: value
  defp granularities_to_string(_), do: ""

  defp format_expire_after(nil), do: "never"

  defp format_expire_after(seconds) when is_integer(seconds) and seconds > 0 do
    cond do
      rem(seconds, 86_400) == 0 -> "#{div(seconds, 86_400)}d"
      rem(seconds, 3_600) == 0 -> "#{div(seconds, 3_600)}h"
      rem(seconds, 60) == 0 -> "#{div(seconds, 60)}m"
      true -> "#{seconds}s"
    end
  end

  defp format_expire_after(seconds) when is_binary(seconds) do
    seconds
    |> Integer.parse()
    |> case do
      {value, _} -> format_expire_after(value)
      :error -> "never"
    end
  end

  defp format_expire_after(_), do: "never"

  defp project_list_meta(%Project{} = project) do
    []
    |> maybe_add_meta(project.default_timeframe, fn timeframe ->
      "Default timeframe #{timeframe}"
    end)
    |> maybe_add_meta(project.expire_after, fn expire ->
      "Retention #{format_expire_after(expire)}"
    end)
  end

  defp maybe_add_meta(acc, value, _fun) when value in [nil, ""], do: acc
  defp maybe_add_meta(acc, value, fun), do: acc ++ [fun.(value)]
end
