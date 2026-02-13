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
            field={@form[:expire_after]}
            type="select"
            label="Data retention"
            options={project_retention_options()}
            prompt="Select a retention policy"
            help_text="Choose once at project creation. Retention cannot be changed later."
            required
          />

          <div class="space-y-2">
            <label
              for={@form[:project_cluster_id].id}
              class="block text-sm font-medium text-gray-900 dark:text-white"
            >
              Datacenter location
            </label>
            <div class="grid grid-cols-1">
              <select
                id={@form[:project_cluster_id].id}
                name={@form[:project_cluster_id].name}
                class={[
                  "col-start-1 row-start-1 w-full appearance-none rounded-lg bg-white dark:bg-slate-700 py-2 pr-8 pl-3 text-base text-gray-900 dark:text-white outline-1 -outline-offset-1 outline-gray-300 dark:outline-slate-600 focus:outline-2 focus:-outline-offset-2 focus:outline-teal-600 sm:text-sm",
                  @form[:project_cluster_id].errors != [] && "outline-red-400 focus:outline-red-400"
                ]}
                required
              >
                <option value="">Select a datacenter</option>
                <%= for option <- @project_cluster_options do %>
                  <option
                    value={option.id}
                    disabled={option.disabled}
                    selected={to_string(option.id) == to_string(@form[:project_cluster_id].value)}
                  >
                    {option.label}
                  </option>
                <% end %>
              </select>
              <svg
                class="col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-400 dark:text-slate-500 sm:h-4 sm:w-4"
                viewBox="0 0 16 16"
                fill="currentColor"
                aria-hidden="true"
              >
                <path
                  fill-rule="evenodd"
                  d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z"
                  clip-rule="evenodd"
                />
              </svg>
            </div>
            <p class="text-xs text-gray-600 dark:text-gray-400">
              Choose where metrics are stored. Restricted locations require approval.
            </p>
            <.form_errors field={@form[:project_cluster_id]} />
          </div>

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

          <:actions>
            <.form_actions>
              <.secondary_button patch={~p"/projects"}>
                Cancel
              </.secondary_button>
              <.primary_button phx-disable-with="Creating...">Create project</.primary_button>
            </.form_actions>
          </:actions>
        </.form_container>
      </:body>
    </.app_modal>
    """
  end

  def mount(params, _session, socket) do
    membership = socket.assigns.current_membership
    projects = list_projects_for_membership(membership)
    cluster_choices = list_cluster_choices_for_membership(membership)
    default_cluster_id = default_cluster_id(cluster_choices)

    changeset =
      Organizations.change_project(%Project{
        project_cluster_id: default_cluster_id,
        expire_after: Project.basic_retention_seconds()
      })

    socket =
      socket
      |> assign(:projects, projects)
      |> assign(:form, to_form(changeset))
      |> assign(:time_zones, time_zones())
      |> assign(:week_options, @week_options)
      |> assign(:project_cluster_choices, cluster_choices)
      |> assign(:project_cluster_options, cluster_options(cluster_choices))
      |> assign(:page_title, "Projects")
      |> assign(:show_new_modal, false)

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    cluster_choices = socket.assigns.project_cluster_choices
    default_cluster_id = default_cluster_id(cluster_choices)

    socket
    |> assign(:page_title, "Projects · New")
    |> assign(:show_new_modal, true)
    |> assign(
      :form,
      to_form(
        Organizations.change_project(%Project{
          project_cluster_id: default_cluster_id,
          expire_after: Project.basic_retention_seconds()
        })
      )
    )
  end

  defp apply_action(socket, :index, _params) do
    membership = socket.assigns.current_membership

    socket
    |> assign(:page_title, "Projects")
    |> assign(:show_new_modal, false)
    |> assign(:projects, list_projects_for_membership(membership))
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
    membership = socket.assigns.current_membership

    case create_project_for_membership(project_params, membership, socket.assigns.current_user) do
      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:ok, project} ->
        cluster_choices = list_cluster_choices_for_membership(membership)
        default_cluster_id = default_cluster_id(cluster_choices)

        socket =
          socket
          |> put_flash(:info, "#{project.name} created")
          |> assign(:projects, list_projects_for_membership(membership))
          |> assign(:project_cluster_choices, cluster_choices)
          |> assign(:project_cluster_options, cluster_options(cluster_choices))
          |> assign(
            :form,
            to_form(
              Organizations.change_project(%Project{
                project_cluster_id: default_cluster_id,
                expire_after: Project.basic_retention_seconds()
              })
            )
          )
          |> assign(:show_new_modal, false)

        {:noreply, push_patch(socket, to: ~p"/projects")}
    end
  end

  def handle_event("open_settings", %{"id" => project_id}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{project_id}/settings")}
  end

  def handle_event("close_new_modal", _params, socket) do
    {:noreply, push_patch(assign(socket, :show_new_modal, false), to: ~p"/projects")}
  end

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

  defp list_projects_for_membership(nil), do: []

  defp list_projects_for_membership(membership) do
    Organizations.list_projects_for_membership(membership)
  end

  defp list_cluster_choices_for_membership(nil), do: []

  defp list_cluster_choices_for_membership(%{organization_id: organization_id}) do
    Organizations.list_project_clusters_for_org(organization_id)
  end

  defp create_project_for_membership(_attrs, nil, _user) do
    {:error,
     Organizations.change_project(%Project{expire_after: Project.basic_retention_seconds()})}
  end

  defp create_project_for_membership(attrs, membership, user) do
    Organizations.create_project_for_membership(attrs, membership, user)
  end

  defp cluster_options(cluster_choices) do
    Enum.map(cluster_choices, fn %{cluster: cluster, selectable: selectable, reason: reason} ->
      %{
        id: cluster.id,
        label: cluster_option_label(cluster, reason),
        disabled: !selectable
      }
    end)
  end

  defp cluster_option_label(cluster, reason) do
    location =
      [cluster.region, cluster.city, cluster.country]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" · ")

    base =
      if location == "" do
        cluster.name
      else
        "#{cluster.name} · #{location}"
      end

    suffix =
      case reason do
        :coming_soon -> " (Coming soon)"
        :contact_sales -> " (Contact sales)"
        _ -> ""
      end

    base <> suffix
  end

  defp default_cluster_id([]), do: nil

  defp default_cluster_id(cluster_choices) do
    cluster_choices
    |> Enum.find(fn %{cluster: cluster, selectable: selectable} ->
      selectable && cluster.is_default
    end)
    |> case do
      nil ->
        case Enum.find(cluster_choices, & &1.selectable) do
          nil -> nil
          %{cluster: cluster} -> cluster.id
        end

      %{cluster: cluster} ->
        cluster.id
    end
  end

  defp project_retention_options do
    Project.retention_options()
  end

  defp project_list_meta(%Project{} = project) do
    []
    |> maybe_add_meta(project.default_timeframe, fn timeframe ->
      "Default timeframe #{timeframe}"
    end)
  end

  defp maybe_add_meta(acc, value, _fun) when value in [nil, ""], do: acc
  defp maybe_add_meta(acc, value, fun), do: acc ++ [fun.(value)]
end
