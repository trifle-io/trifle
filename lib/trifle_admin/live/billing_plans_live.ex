defmodule TrifleAdmin.BillingPlansLive do
  use TrifleAdmin, :live_view

  alias Phoenix.LiveView.JS
  alias Trifle.Billing
  alias Trifle.Billing.Plan
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()
  @scope_options [{"All", "all"}, {"App", "app"}, {"Project", "project"}]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Billing Plans",
       plans: [],
       plan: nil,
       query: "",
       scope: "all",
       scope_options: @scope_options,
       pagination: Pagination.build(0, 1, @page_size)
     )}
  end

  def handle_params(params, _url, socket) do
    query = Pagination.sanitize_query(Map.get(params, "q", ""))
    page = Pagination.parse_page(params["page"])
    scope = normalize_scope(Map.get(params, "scope", "all"))
    {plans, pagination} = list_plans(query, scope, page)

    socket =
      socket
      |> assign(plans: plans, pagination: pagination, query: query, scope: scope)
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  def handle_event("filter", %{"q" => query}, socket) do
    push_filter_patch(socket, query, socket.assigns.scope)
  end

  def handle_event("filter", %{"scope" => scope}, socket) do
    push_filter_patch(socket, socket.assigns.query, scope)
  end

  def handle_event("filter", %{"filters" => filters}, socket) do
    query = Map.get(filters, "q", socket.assigns.query)
    scope = Map.get(filters, "scope", socket.assigns.scope)
    push_filter_patch(socket, query, scope)
  end

  def handle_event("toggle_active", %{"id" => id}, socket) do
    case Repo.get(Plan, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Billing plan not found.")}

      %Plan{} = plan ->
        case Billing.set_billing_plan_active(plan, !plan.active) do
          {:ok, _updated} ->
            {:noreply,
             socket
             |> put_flash(:info, "Billing plan updated.")
             |> refresh_list()
             |> refresh_modal_plan()}

          {:error, %Ecto.Changeset{} = changeset} ->
            errors =
              changeset.errors
              |> Enum.map(fn {field, {msg, _opts}} -> "#{field} #{msg}" end)
              |> Enum.join(", ")

            {:noreply, put_flash(socket, :error, "Could not update plan: #{errors}")}
        end
    end
  end

  def handle_info({TrifleAdmin.BillingPlansLive.FormComponent, {:saved, _plan}}, socket) do
    {:noreply, socket |> refresh_list() |> refresh_modal_plan()}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Billing Plans · New")
    |> assign(:plan, %Plan{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    plan =
      Repo.get!(Plan, id)
      |> Repo.preload(:organization)

    socket
    |> assign(:page_title, "Billing Plans · Edit")
    |> assign(:plan, plan)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    plan =
      Repo.get!(Plan, id)
      |> Repo.preload(:organization)

    socket
    |> assign(:page_title, "Billing Plans")
    |> assign(:plan, plan)
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Billing Plans")
    |> assign(:plan, nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Billing Plans"
          description="Manage Stripe price mapping and published plan catalog."
        >
          <:actions>
            <div class="flex items-center gap-3">
              <.form for={%{}} as={:filters} phx-change="filter" class="w-[30rem]">
                <div class="flex gap-2">
                  <input
                    type="search"
                    name="q"
                    value={@query}
                    placeholder="Search by name, scope, tier, price ID..."
                    phx-debounce="300"
                    autocomplete="off"
                    class="block w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
                  />
                  <select
                    name="scope"
                    class="rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:text-white"
                  >
                    <%= for {label, value} <- @scope_options do %>
                      <option value={value} selected={@scope == value}>{label}</option>
                    <% end %>
                  </select>
                </div>
              </.form>
              <.link
                patch={~p"/admin/billing/plans/new?#{list_params(@query, @scope, @pagination.page)}"}
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
              >
                New Plan
              </.link>
            </div>
          </:actions>
        </.admin_table_header>
      </:header>

      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Name</.admin_table_column>
              <.admin_table_column>Organization</.admin_table_column>
              <.admin_table_column>Scope</.admin_table_column>
              <.admin_table_column>Tier</.admin_table_column>
              <.admin_table_column>Interval</.admin_table_column>
              <.admin_table_column>Amount</.admin_table_column>
              <.admin_table_column>Status</.admin_table_column>
              <.admin_table_column actions />
            </:columns>

            <:rows>
              <%= for plan <- @plans do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/billing/plans/#{plan}/show?#{list_params(@query, @scope, @pagination.page)}"
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
                              d="M12 8c-2.21 0-4 .895-4 2s1.79 2 4 2 4 .895 4 2-1.79 2-4 2m0-10V6m0 12v-2m0-8c2.21 0 4-.895 4-2s-1.79-2-4-2-4 .895-4 2 1.79 2 4 2z"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200 truncate">
                          {plan.name}
                        </p>
                        <p class="text-xs font-mono text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200 truncate">
                          {plan.stripe_price_id}
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
                    {organization_label(plan)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {plan.scope_type}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <span class="text-gray-900 dark:text-white">{plan.tier_key}</span>
                      <span class="text-xs text-gray-500 dark:text-gray-400">
                        <%= if plan.retention_add_on do %>
                          retention add-on
                        <% else %>
                          base plan
                        <% end %>
                      </span>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <span class="text-gray-900 dark:text-white">{plan.interval}</span>
                      <span :if={plan.founder_offer} class="text-xs text-teal-600 dark:text-teal-300">
                        founder offer
                      </span>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    {format_amount(plan.amount_cents, plan.currency)}
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <%= if plan.active do %>
                      <.status_badge variant="success">Active</.status_badge>
                    <% else %>
                      <.status_badge variant="pending">Inactive</.status_badge>
                    <% end %>
                  </.admin_table_cell>
                  <.admin_table_cell actions>
                    <div class="flex items-center justify-end gap-3">
                      <.link
                        patch={
                          ~p"/admin/billing/plans/#{plan}/edit?#{list_params(@query, @scope, @pagination.page)}"
                        }
                        class="text-sm font-medium text-teal-600 hover:text-teal-700 dark:text-teal-400 dark:hover:text-teal-300"
                      >
                        Edit
                      </.link>
                      <.table_action_button
                        variant={if plan.active, do: "danger", else: "primary"}
                        phx_click="toggle_active"
                        phx_value_id={plan.id}
                      >
                        {if plan.active, do: "Deactivate", else: "Activate"}
                      </.table_action_button>
                    </div>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/billing/plans"}
          params={list_params(@query, @scope, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action in [:new, :edit]}
      id="billing-plan-form-modal"
      show
      on_cancel={JS.patch(~p"/admin/billing/plans?#{list_params(@query, @scope, @pagination.page)}")}
      size="lg"
    >
      <:title>
        <%= if @live_action == :new do %>
          New Billing Plan
        <% else %>
          Edit Billing Plan
        <% end %>
      </:title>
      <:body>
        <.live_component
          module={TrifleAdmin.BillingPlansLive.FormComponent}
          id={@plan.id || :new}
          plan={@plan}
          action={@live_action}
          patch={~p"/admin/billing/plans?#{list_params(@query, @scope, @pagination.page)}"}
        />
      </:body>
    </.app_modal>

    <.app_modal
      :if={@live_action == :show}
      id="billing-plan-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/billing/plans?#{list_params(@query, @scope, @pagination.page)}")}
      size="lg"
    >
      <:title>Billing Plan Details</:title>
      <:body>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Name</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@plan.name}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {organization_label(@plan)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Scope</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@plan.scope_type}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Tier Key</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@plan.tier_key}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Interval</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@plan.interval}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Stripe Price ID</dt>
              <dd class="mt-1 text-sm font-mono text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 break-all">
                {@plan.stripe_price_id}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Amount</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_amount(@plan.amount_cents, @plan.currency)}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Seat Limit</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@plan.seat_limit || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Hard Limit</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@plan.hard_limit || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Flags</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                <div class="flex flex-wrap gap-2">
                  <span class={flag_badge_class(@plan.active)}>
                    {if @plan.active, do: "active", else: "inactive"}
                  </span>
                  <span class={flag_badge_class(@plan.retention_add_on)}>
                    {if @plan.retention_add_on, do: "retention add-on", else: "no retention"}
                  </span>
                  <span class={flag_badge_class(@plan.founder_offer)}>
                    {if @plan.founder_offer, do: "founder offer", else: "standard"}
                  </span>
                </div>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Metadata</dt>
              <dd class="mt-1 text-xs font-mono text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                <pre class="overflow-x-auto rounded-md bg-gray-50 dark:bg-slate-900 p-3">{Jason.encode!(@plan.metadata || %{}, pretty: true)}</pre>
              </dd>
            </div>
          </dl>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp push_filter_patch(socket, query, scope) do
    query = Pagination.sanitize_query(query)
    scope = normalize_scope(scope)

    {:noreply, push_patch(socket, to: ~p"/admin/billing/plans?#{list_params(query, scope, 1)}")}
  end

  defp refresh_list(socket) do
    {plans, pagination} =
      list_plans(socket.assigns.query, socket.assigns.scope, socket.assigns.pagination.page)

    assign(socket, plans: plans, pagination: pagination)
  end

  defp refresh_modal_plan(%{assigns: %{plan: nil}} = socket), do: socket

  defp refresh_modal_plan(%{assigns: %{plan: %Plan{id: id}}} = socket) do
    assign(socket, :plan, Repo.get!(Plan, id) |> Repo.preload(:organization))
  end

  defp list_plans(query, scope, page) do
    query
    |> Billing.admin_plans_query(scope)
    |> Pagination.paginate(page, @page_size)
  end

  defp list_params(query, scope, page) do
    params = Pagination.list_params(query, page)

    case scope do
      "all" -> params
      _ -> Keyword.put(params, :scope, scope)
    end
  end

  defp normalize_scope(scope) when scope in ["all", "app", "project"], do: scope
  defp normalize_scope(_), do: "all"

  defp organization_label(%Plan{organization: %{name: name}}), do: name
  defp organization_label(%Plan{organization_id: nil}), do: "Global"
  defp organization_label(%Plan{organization_id: organization_id}), do: organization_id

  defp format_amount(nil, _currency), do: "N/A"

  defp format_amount(amount_cents, currency),
    do: Billing.format_amount(amount_cents, currency || "usd")

  defp flag_badge_class(true),
    do:
      "inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/20"

  defp flag_badge_class(false),
    do:
      "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-700 ring-1 ring-inset ring-gray-600/20"
end
