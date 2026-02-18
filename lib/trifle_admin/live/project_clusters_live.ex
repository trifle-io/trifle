defmodule TrifleAdmin.ProjectClustersLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Phoenix.LiveView.JS
  alias Trifle.Organizations
  alias Trifle.Organizations.ProjectCluster
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Project Clusters",
       clusters: [],
       project_cluster: nil,
       query: "",
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])
    {clusters, pagination} = list_project_clusters(query, page)

    socket =
      socket
      |> assign(clusters: clusters, pagination: pagination, query: query)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply,
     push_patch(socket, to: ~p"/admin/project-clusters?#{Pagination.list_params(query, 1)}")}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  def handle_info({TrifleAdmin.ProjectClustersLive.FormComponent, {:saved, _cluster}}, socket) do
    {clusters, pagination} =
      list_project_clusters(socket.assigns.query, socket.assigns.pagination.page)

    {:noreply, assign(socket, clusters: clusters, pagination: pagination)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Project Clusters · New")
    |> assign(:project_cluster, %ProjectCluster{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    project_cluster = Organizations.get_project_cluster!(id)

    socket
    |> assign(:page_title, "Project Clusters · Edit")
    |> assign(:project_cluster, project_cluster)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    project_cluster =
      id
      |> Organizations.get_project_cluster!()
      |> Repo.preload(:project_cluster_accesses)

    socket
    |> assign(:page_title, "Project Clusters")
    |> assign(:project_cluster, project_cluster)
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, project_cluster: nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Project Clusters"
          description="Manage datacenter clusters for project storage."
        >
          <:actions>
            <div class="flex items-center gap-3">
              <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
                <input
                  type="search"
                  name="q"
                  value={@query}
                  placeholder="Search clusters..."
                  phx-debounce="300"
                  autocomplete="off"
                  class="block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
                />
              </.form>
              <.link
                patch={~p"/admin/project-clusters/new"}
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
              >
                New Cluster
              </.link>
            </div>
          </:actions>
        </.admin_table_header>
      </:header>

      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Cluster</.admin_table_column>
              <.admin_table_column>Code</.admin_table_column>
              <.admin_table_column>Driver</.admin_table_column>
              <.admin_table_column>Status</.admin_table_column>
              <.admin_table_column>Visibility</.admin_table_column>
              <.admin_table_column>Default</.admin_table_column>
              <.admin_table_column actions />
            </:columns>

            <:rows>
              <%= for cluster <- @clusters do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/project-clusters/#{cluster}/show?#{Pagination.list_params(@query, @pagination.page)}"
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
                              d="M5.25 14.25h13.5m-13.5 0a3 3 0 0 1-3-3m3 3a3 3 0 1 0 0 6h13.5a3 3 0 1 0 0-6m-16.5-3a3 3 0 0 1 3-3h13.5a3 3 0 0 1 3 3m-19.5 0a4.5 4.5 0 0 1 .9-2.7L5.737 5.1a3.375 3.375 0 0 1 2.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 0 1 .9 2.7m0 0a3 3 0 0 1-3 3m0 3h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Zm-3 6h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Z"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {cluster.name}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200">
                          {cluster.region || cluster.city || cluster.country || ""}
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
                    {cluster.code}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {String.capitalize(cluster.driver)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <%= if cluster.status == "active" do %>
                      <.status_badge variant="success">Active</.status_badge>
                    <% else %>
                      <.status_badge variant="pending">Coming soon</.status_badge>
                    <% end %>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {String.capitalize(cluster.visibility)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <%= if cluster.is_default do %>
                      <.status_badge variant="info">Default</.status_badge>
                    <% else %>
                      <span class="text-sm text-gray-500 dark:text-gray-400">—</span>
                    <% end %>
                  </.admin_table_cell>
                  <.admin_table_cell actions>
                    <.link
                      patch={
                        ~p"/admin/project-clusters/#{cluster}/edit?#{Pagination.list_params(@query, @pagination.page)}"
                      }
                      class="text-sm font-medium text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300"
                    >
                      Edit
                    </.link>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/project-clusters"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action in [:new, :edit]}
      id="project-cluster-form-modal"
      show
      on_cancel={
        JS.patch(~p"/admin/project-clusters?#{Pagination.list_params(@query, @pagination.page)}")
      }
    >
      <:title>
        <%= if @live_action == :new do %>
          New Project Cluster
        <% else %>
          Edit Project Cluster
        <% end %>
      </:title>
      <:body>
        <.live_component
          module={TrifleAdmin.ProjectClustersLive.FormComponent}
          id={@project_cluster.id || :new}
          project_cluster={@project_cluster}
          action={@live_action}
          patch={~p"/admin/project-clusters"}
        />
      </:body>
    </.app_modal>

    <.app_modal
      :if={@live_action == :show}
      id="project-cluster-details-modal"
      show
      on_cancel={
        JS.patch(~p"/admin/project-clusters?#{Pagination.list_params(@query, @pagination.page)}")
      }
    >
      <:title>Project Cluster Details</:title>
      <:body>
        <.live_component
          module={TrifleAdmin.ProjectClustersLive.DetailsComponent}
          id={@project_cluster.id}
          project_cluster={@project_cluster}
        />
      </:body>
    </.app_modal>
    """
  end

  defp list_project_clusters(query, page) do
    base_query =
      from(c in ProjectCluster,
        order_by: [asc: c.name, asc: c.id]
      )

    base_query
    |> filter_project_clusters(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp filter_project_clusters(query, ""), do: query

  defp filter_project_clusters(query, term) do
    like = "%#{term}%"

    from(c in query,
      where:
        ilike(c.name, ^like) or
          ilike(c.code, ^like) or
          ilike(c.driver, ^like) or
          ilike(c.status, ^like) or
          ilike(c.visibility, ^like) or
          ilike(c.region, ^like) or
          ilike(c.city, ^like) or
          ilike(c.country, ^like) or
          ilike(fragment("CAST(? AS text)", c.id), ^like)
    )
  end
end
