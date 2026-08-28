defmodule TrifleAdmin.DashboardTemplatesLive do
  use TrifleAdmin, :live_view

  import Ecto.Query, warn: false

  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.DashboardTemplate
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Dashboard Templates",
       templates: [],
       template: nil,
       usage_counts: %{},
       query: "",
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])

    socket =
      socket
      |> assign_templates(query, page)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    query = Pagination.sanitize_query(query)

    {:noreply,
     push_patch(socket,
       to: ~p"/admin/dashboard-templates?#{Pagination.list_params(query, 1)}"
     )}
  end

  def handle_event("filter", %{"filters" => %{"q" => query}}, socket) do
    handle_event("filter", %{"q" => query}, socket)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    template =
      DashboardTemplate
      |> Repo.get!(id)
      |> Repo.preload([:organization, :created_by])

    assign(socket,
      template: template,
      usage_counts:
        Map.put(
          socket.assigns.usage_counts,
          template.id,
          Organizations.dashboard_template_usage_count(template)
        )
    )
  end

  defp apply_action(socket, :index, _params), do: assign(socket, template: nil)

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Dashboard Templates"
          description="Inspect organization-owned user templates. Hardcoded system templates are not listed here."
        >
          <:actions>
            <.form for={%{}} as={:filters} phx-change="filter" class="w-64">
              <input
                type="search"
                name="q"
                value={@query}
                placeholder="Search templates..."
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
              <.admin_table_column first>Template</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
              <.admin_table_column>Creator</.admin_table_column>
              <.admin_table_column>Dashboards</.admin_table_column>
              <.admin_table_column>Version</.admin_table_column>
              <.admin_table_column>Updated</.admin_table_column>
            </:columns>

            <:rows>
              <%= for template <- @templates do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/dashboard-templates/#{template}/show?#{Pagination.list_params(@query, @pagination.page)}"
                      }
                      class="group flex items-center space-x-3 text-gray-900 transition-all duration-200 hover:text-teal-600 dark:text-white dark:hover:text-teal-400"
                    >
                      <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-teal-50 to-blue-50 transition group-hover:from-teal-100 group-hover:to-blue-100 dark:from-teal-900 dark:to-blue-900">
                        <TrifleApp.SidebarIcons.icon
                          name="sidebar-dashboards"
                          class="h-5 w-5 text-teal-600 dark:text-teal-400"
                        />
                      </div>
                      <div class="min-w-0 flex-1">
                        <p class="truncate text-sm font-semibold">{template.name}</p>
                        <p class="truncate font-mono text-xs text-gray-500 dark:text-gray-400">
                          user:{template.id}
                        </p>
                      </div>
                    </.link>
                  </.admin_table_cell>
                  <.admin_table_cell>{organization_name(template)}</.admin_table_cell>
                  <.admin_table_cell>{creator_email(template)}</.admin_table_cell>
                  <.admin_table_cell>
                    {Map.get(@usage_counts, template.id, 0)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <.status_badge>v{template.lock_version}</.status_badge>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <span class="text-gray-900 dark:text-white">
                        {Calendar.strftime(template.updated_at, "%Y-%m-%d")}
                      </span>
                      <span class="text-xs text-gray-400 dark:text-gray-500">
                        {Calendar.strftime(template.updated_at, "%H:%M")} UTC
                      </span>
                    </div>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/dashboard-templates"}
          params={Pagination.list_params(@query, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="dashboard-template-details-modal"
      show
      on_cancel={
        JS.patch(~p"/admin/dashboard-templates?#{Pagination.list_params(@query, @pagination.page)}")
      }
      size="xl"
    >
      <:title>Dashboard Template Details</:title>
      <:body>
        <div class="border-t border-gray-200 pt-6 dark:border-slate-600">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <.detail label="Name">{@template.name}</.detail>
            <.detail label="Reference">
              <span class="break-all font-mono">user:{@template.id}</span>
            </.detail>
            <.detail label="Organization">{organization_name(@template)}</.detail>
            <.detail label="Creator">{creator_email(@template)}</.detail>
            <.detail label="Linked dashboards">
              {Map.get(@usage_counts, @template.id, 0)}
            </.detail>
            <.detail label="Version">{@template.lock_version}</.detail>
            <.detail label="Created">{format_datetime(@template.inserted_at)}</.detail>
            <.detail label="Updated">{format_datetime(@template.updated_at)}</.detail>
            <.detail label="Payload">
              <pre class="max-h-96 overflow-auto whitespace-pre-wrap break-all rounded-lg bg-slate-50 p-4 font-mono text-xs text-slate-800 dark:bg-slate-950 dark:text-slate-100">{Jason.encode!(@template.payload || %{}, pretty: true)}</pre>
            </.detail>
          </dl>
        </div>
      </:body>
    </.app_modal>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail(assigns) do
    ~H"""
    <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
      <dt class="text-sm font-medium text-gray-900 dark:text-white">{@label}</dt>
      <dd class="mt-1 text-sm text-gray-700 sm:col-span-2 sm:mt-0 dark:text-slate-300">
        {render_slot(@inner_block)}
      </dd>
    </div>
    """
  end

  defp assign_templates(socket, query, page) do
    {templates, pagination} = list_templates(query, page)

    assign(socket,
      templates: templates,
      pagination: pagination,
      query: query,
      usage_counts: Organizations.dashboard_template_usage_counts(templates)
    )
  end

  defp list_templates(query, page) do
    from(t in DashboardTemplate,
      join: o in assoc(t, :organization),
      left_join: u in User,
      on: u.id == t.created_by_id,
      order_by: [asc: fragment("lower(?)", t.name), asc: t.id],
      preload: [organization: o, created_by: u]
    )
    |> filter_templates(query)
    |> Pagination.paginate(page, @page_size)
  end

  defp filter_templates(query, ""), do: query

  defp filter_templates(query, term) do
    like = "%#{term}%"

    from([t, o, u] in query,
      where:
        ilike(t.name, ^like) or
          ilike(o.name, ^like) or
          ilike(o.slug, ^like) or
          ilike(u.email, ^like) or
          ilike(u.name, ^like) or
          ilike(fragment("CAST(? AS text)", t.id), ^like)
    )
  end

  defp organization_name(%{organization: %{name: name}}), do: name
  defp organization_name(_template), do: "N/A"

  defp creator_email(%{created_by: %{email: email}}), do: email
  defp creator_email(_template), do: "Deleted user"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p UTC")
  end
end
