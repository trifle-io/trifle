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

  defp apply_action(socket, :show, %{"id" => id}) do
    project =
      id
      |> Organizations.get_project!()
      |> Repo.preload([:user, :organization, :project_cluster])

    assign(socket, project: project)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, project: nil)
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
                            class="w-5 h-5 text-teal-600 dark:text-teal-400"
                            fill="none"
                            stroke="currentColor"
                            viewBox="0 0 24 24"
                          >
                            <path
                              stroke-linecap="round"
                              stroke-linejoin="round"
                              stroke-width="2"
                              d="M3 7a2 2 0 012-2h5l2 2h7a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2V7z"
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

  defp owner_email(%Project{user: %{email: email}}), do: email
  defp owner_email(%Project{user: nil}), do: "N/A"
  defp owner_email(_), do: "N/A"

  defp organization_name(%Project{organization: %Organization{name: name}}), do: name
  defp organization_name(_), do: nil

  defp format_beginning_of_week(%Project{} = project) do
    project
    |> Project.beginning_of_week_for()
    |> case do
      nil -> "N/A"
      value -> value |> Atom.to_string() |> String.capitalize()
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
