defmodule TrifleAdmin.ProjectsLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Trifle.Organizations
  alias Trifle.Organizations.Project
  alias Trifle.Organizations.Organization
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Projects",
       projects: [],
       project: nil,
       project_subscription: nil,
       can_delete_project: false,
       project_delete_reason: nil,
       query: "",
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])

    socket =
      socket
      |> assign_projects(query, page)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply, push_patch(socket, to: ~p"/admin/projects?#{Pagination.list_params(query, 1)}")}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  def handle_event("delete_project", %{"id" => id}, socket) do
    project = Organizations.get_project!(id)

    case Organizations.delete_project(project) do
      {:ok, _deleted_project} ->
        list_path =
          ~p"/admin/projects?#{Pagination.list_params(socket.assigns.query, socket.assigns.pagination.page)}"

        {:noreply,
         socket
         |> put_flash(:info, "Project deleted successfully.")
         |> push_patch(to: list_path)}

      {:error, :active_subscription} ->
        refreshed_project = load_project(id)

        {:noreply,
         socket
         |> assign_project_details(refreshed_project)
         |> put_flash(
           :error,
           Organizations.project_delete_block_reason(refreshed_project) ||
             "Project cannot be deleted while its subscription is active."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Project could not be deleted.")}
    end
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign_project_details(load_project(id))
  end

  defp apply_action(socket, :index, _params) do
    assign(socket,
      project: nil,
      project_subscription: nil,
      can_delete_project: false,
      project_delete_reason: nil
    )
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header title="Projects" description="Browse all projects and owners.">
          <:actions>
            <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
              <input
                type="search"
                name="q"
                value={@query}
                placeholder="Search projects..."
                phx-debounce="300"
                autocomplete="off"
                class="block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
              />
            </.form>
          </:actions>
        </.admin_table_header>
      </:header>

      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Project</.admin_table_column>
              <.admin_table_column>Owner</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
              <.admin_table_column>Time Zone</.admin_table_column>
              <.admin_table_column>Data Retention</.admin_table_column>
              <.admin_table_column>Created</.admin_table_column>
            </:columns>

            <:rows>
              <%= for project <- @projects do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/projects/#{project}/show?#{Pagination.list_params(@query, @pagination.page)}"
                      }
                      class="group flex items-center space-x-3 text-gray-900 dark:text-white hover:text-teal-600 dark:hover:text-teal-400 transition-all duration-200 cursor-pointer"
                    >
                      <div class="flex-shrink-0">
                        <div class="w-10 h-10 bg-gradient-to-br from-teal-50 to-blue-50 dark:from-teal-900 dark:to-blue-900 rounded-lg flex items-center justify-center group-hover:from-teal-100 group-hover:to-blue-100 dark:group-hover:from-teal-800 dark:group-hover:to-blue-800 transition-all duration-200">
                          <svg
                            xmlns="http://www.w3.org/2000/svg"
                            fill="none"
                            viewBox="0 0 24 24"
                            stroke-width="1.5"
                            stroke="currentColor"
                            class="w-5 h-5 text-teal-600 dark:text-teal-400"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              d="M2.25 12.75V12A2.25 2.25 0 0 1 4.5 9.75h15A2.25 2.25 0 0 1 21.75 12v.75m-8.69-6.44-2.12-2.12a1.5 1.5 0 0 0-1.061-.44H4.5A2.25 2.25 0 0 0 2.25 6v12a2.25 2.25 0 0 0 2.25 2.25h15A2.25 2.25 0 0 0 21.75 18V9a2.25 2.25 0 0 0-2.25-2.25h-5.379a1.5 1.5 0 0 1-1.06-.44Z"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {project.name}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200">
                          Default timeframe: {project.default_timeframe || "Not set"}
                        </p>
                      </div>
                      <div class="flex-shrink-0">
                        <svg
                          class="w-4 h-4 text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M9 5l7 7-7 7"
                          />
                        </svg>
                      </div>
                    </.link>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {owner_email(project)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {organization_name(project) || "N/A"}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {project.time_zone || "N/A"}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20 dark:bg-blue-500/10 dark:text-blue-200 dark:ring-blue-400/30">
                      {retention_label(project)}
                    </span>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <div class="text-gray-900 dark:text-white">
                        {Calendar.strftime(project.inserted_at, "%Y-%m-%d")}
                      </div>
                      <div class="text-xs text-gray-400 dark:text-gray-500">
                        {Calendar.strftime(project.inserted_at, "%H:%M")} UTC
                      </div>
                    </div>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/projects"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="project-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/projects?#{Pagination.list_params(@query, @pagination.page)}")}
      size="lg"
    >
      <:title>Project Details</:title>
      <:body>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Name</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@project.name}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Owner</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {owner_email(@project)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {organization_name(@project) || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Project Cluster</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {if @project.project_cluster, do: @project.project_cluster.name, else: "Default"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Time Zone</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@project.time_zone || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Data Retention</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {retention_label(@project)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Beginning of Week</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_beginning_of_week(@project)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Granularities</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                <%= if @project.granularities && length(@project.granularities) > 0 do %>
                  <div class="flex flex-wrap gap-1">
                    <%= for granularity <- @project.granularities do %>
                      <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                        {granularity}
                      </span>
                    <% end %>
                  </div>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">N/A</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Default Timeframe</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if @project.default_timeframe && @project.default_timeframe != "" do %>
                  <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                    {@project.default_timeframe}
                  </span>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Default Granularity</dt>
              <dd class="mt-1 sm:col-span-2 sm:mt-0">
                <%= if @project.default_granularity && @project.default_granularity != "" do %>
                  <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                    {@project.default_granularity}
                  </span>
                <% else %>
                  <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Project ID</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
                {@project.id}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Created</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@project.inserted_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Updated</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@project.updated_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
          </dl>
        </div>

        <div class="mt-8 overflow-hidden rounded-lg border border-red-200 bg-white dark:border-red-900/40 dark:bg-slate-900">
          <div class="px-4 py-6 sm:px-6">
            <div class="flex items-center justify-between gap-4">
              <div>
                <h3 class="text-base/7 font-semibold text-gray-900 dark:text-white">
                  Danger zone
                </h3>
                <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
                  Deleting a project permanently removes the project record, its linked transponders,
                  and its inactive subscription.
                </p>
              </div>

              <%= if @project_subscription do %>
                <.status_badge variant={subscription_status_variant(@project_subscription.status)}>
                  Subscription: {@project_subscription.status || "unknown"}
                </.status_badge>
              <% end %>
            </div>
          </div>

          <div class="border-t border-red-100 px-4 py-5 sm:px-6 dark:border-red-900/40">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div class="max-w-xl text-sm text-gray-600 dark:text-slate-300">
                <p :if={@can_delete_project}>
                  This action cannot be undone.
                </p>
                <p :if={!@can_delete_project}>
                  {@project_delete_reason || "This project cannot be deleted right now."}
                </p>
              </div>

              <button
                phx-click="delete_project"
                phx-value-id={@project.id}
                type="button"
                disabled={!@can_delete_project}
                data-confirm={
                  if @can_delete_project do
                    "Are you sure you want to delete this project? This action cannot be undone."
                  end
                }
                class={[
                  "inline-flex items-center rounded-md px-3 py-2 text-sm font-semibold shadow-sm focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2",
                  if(@can_delete_project,
                    do: "bg-red-600 text-white hover:bg-red-500 focus-visible:outline-red-600",
                    else:
                      "cursor-not-allowed border border-gray-200 bg-gray-100 text-gray-400 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-500"
                  )
                ]}
              >
                Delete project
              </button>
            </div>
          </div>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp list_projects(query, page) do
    base_query =
      from(p in Project,
        join: u in assoc(p, :user),
        left_join: o in assoc(p, :organization),
        order_by: [asc: p.name, asc: p.id],
        distinct: p.id,
        preload: [user: u, organization: o]
      )

    base_query
    |> filter_projects(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp assign_projects(socket, query, page) do
    {projects, pagination} = list_projects(query, page)

    assign(socket,
      projects: projects,
      pagination: pagination,
      query: query
    )
  end

  defp assign_project_details(socket, %Project{} = project) do
    subscription = Organizations.get_project_subscription(project)

    assign(socket,
      project: project,
      project_subscription: subscription,
      can_delete_project: project_deletable?(subscription),
      project_delete_reason: project_delete_reason(subscription)
    )
  end

  defp load_project(id) do
    id
    |> Organizations.get_project!()
    |> Repo.preload([:user, :organization, :project_cluster])
  end

  defp owner_email(%Project{user: %{email: email}}), do: email
  defp owner_email(%Project{user: nil}), do: "N/A"
  defp owner_email(_), do: "N/A"

  defp organization_name(%Project{organization: %Organization{name: name}}), do: name
  defp organization_name(_), do: nil

  defp retention_label(%Project{} = project), do: Project.retention_label(project)
  defp retention_label(_), do: "N/A"

  defp format_beginning_of_week(%Project{} = project) do
    project
    |> Project.beginning_of_week_for()
    |> case do
      nil -> "N/A"
      value -> value |> Atom.to_string() |> String.capitalize()
    end
  end

  defp subscription_status_variant(status) when status in ["active", "trialing"], do: "success"
  defp subscription_status_variant(status) when status in ["past_due", "unpaid"], do: "warning"

  defp subscription_status_variant(status)
       when status in ["canceled", "incomplete", "incomplete_expired", "paused"],
       do: "error"

  defp subscription_status_variant(_), do: "default"

  defp project_deletable?(nil), do: true

  defp project_deletable?(subscription) do
    subscription.status in [nil, "", "canceled", "incomplete", "incomplete_expired", "paused"]
  end

  defp project_delete_reason(nil), do: nil

  defp project_delete_reason(subscription) do
    if project_deletable?(subscription) do
      nil
    else
      "Project can only be deleted when its subscription is inactive."
    end
  end

  defp filter_projects(query, ""), do: query

  defp filter_projects(query, term) do
    like = "%#{term}%"

    from([p, u, o] in query,
      where:
        ilike(p.name, ^like) or
          ilike(u.email, ^like) or
          ilike(u.name, ^like) or
          ilike(o.name, ^like) or
          ilike(o.slug, ^like) or
          ilike(p.time_zone, ^like) or
          ilike(p.default_timeframe, ^like) or
          ilike(p.default_granularity, ^like) or
          ilike(fragment("CAST(? AS text)", p.id), ^like)
    )
  end
end
