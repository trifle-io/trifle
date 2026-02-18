defmodule TrifleAdmin.BillingLive do
  use TrifleAdmin, :live_view

  alias Phoenix.LiveView.JS
  alias Trifle.Billing
  alias Trifle.Billing.Subscription
  alias Trifle.Repo
  alias TrifleAdmin.Pagination

  @page_size Pagination.default_per_page()
  @scope_options [{"All", "all"}, {"App", "app"}, {"Project", "project"}]

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Billing",
       subscriptions: [],
       subscription: nil,
       entitlement: nil,
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
    {subscriptions, pagination} = list_subscriptions(query, scope, page)

    socket =
      socket
      |> assign(
        subscriptions: subscriptions,
        pagination: pagination,
        query: query,
        scope: scope
      )
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

  def handle_event("refresh_entitlement", %{"id" => id}, socket) do
    case Repo.get(Subscription, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Subscription not found.")}

      %Subscription{} = subscription ->
        case Billing.refresh_entitlements!(subscription.organization_id) do
          {:ok, _entitlement} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Entitlement refreshed for organization #{subscription.organization_id}."
             )
             |> refresh_list()
             |> refresh_modal_subscription()}

          {:error, reason} ->
            {:noreply,
             put_flash(socket, :error, "Failed to refresh entitlement: #{format_reason(reason)}")}
        end
    end
  end

  defp push_filter_patch(socket, query, scope) do
    query = Pagination.sanitize_query(query)
    scope = normalize_scope(scope)

    {:noreply, push_patch(socket, to: ~p"/admin/billing?#{list_params(query, scope, 1)}")}
  end

  defp refresh_list(socket) do
    {subscriptions, pagination} =
      list_subscriptions(
        socket.assigns.query,
        socket.assigns.scope,
        socket.assigns.pagination.page
      )

    assign(socket, subscriptions: subscriptions, pagination: pagination)
  end

  defp refresh_modal_subscription(%{assigns: %{subscription: nil}} = socket), do: socket

  defp refresh_modal_subscription(%{assigns: %{subscription: %Subscription{id: id}}} = socket) do
    subscription =
      Repo.get!(Subscription, id)
      |> Repo.preload(:organization)

    assign(socket,
      subscription: subscription,
      entitlement: Billing.get_org_entitlement(subscription.organization_id)
    )
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    subscription =
      Repo.get!(Subscription, id)
      |> Repo.preload(:organization)

    socket
    |> assign(:page_title, "Billing")
    |> assign(:subscription, subscription)
    |> assign(:entitlement, Billing.get_org_entitlement(subscription.organization_id))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Billing")
    |> assign(:subscription, nil)
    |> assign(:entitlement, nil)
  end

  def render(assigns) do
    ~H"""
    <.admin_table>
      <:header>
        <.admin_table_header
          title="Billing Subscriptions"
          description="Manage subscription records and refresh organization entitlements."
        >
          <:actions>
            <div class="flex items-center gap-3">
              <.form for={%{}} as={:filters} phx-change="filter" class="w-[30rem]">
                <div class="flex gap-2">
                  <input
                    type="search"
                    name="q"
                    value={@query}
                    placeholder="Search by org, slug, Stripe IDs, status..."
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
                navigate={~p"/admin/billing/plans"}
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
              >
                Manage Plans
              </.link>
            </div>
          </:actions>
        </.admin_table_header>
      </:header>

      <:body>
        <.admin_table_container>
          <.admin_table_full>
            <:columns>
              <.admin_table_column first>Organization</.admin_table_column>
              <.admin_table_column>Scope</.admin_table_column>
              <.admin_table_column>Status</.admin_table_column>
              <.admin_table_column>Billing Period</.admin_table_column>
              <.admin_table_column>Stripe Price</.admin_table_column>
              <.admin_table_column actions />
            </:columns>

            <:rows>
              <%= for subscription <- @subscriptions do %>
                <tr>
                  <.admin_table_cell first>
                    <.link
                      patch={
                        ~p"/admin/billing/#{subscription}/show?#{list_params(@query, @scope, @pagination.page)}"
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
                              d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 0 0 2.25-2.25V6.75A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25v10.5A2.25 2.25 0 0 0 4.5 19.5Z"
                            />
                          </svg>
                        </div>
                      </div>
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-400 transition-colors duration-200 truncate">
                          {(subscription.organization && subscription.organization.name) ||
                            "Unknown org"}
                        </p>
                        <p class="text-xs text-gray-500 dark:text-gray-400 group-hover:text-teal-500 dark:group-hover:text-teal-400 transition-colors duration-200 truncate">
                          {(subscription.organization && subscription.organization.slug) ||
                            subscription.organization_id}
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
                    <div class="flex flex-col">
                      <span class="text-gray-900 dark:text-white">{subscription.scope_type}</span>
                      <span class="text-xs text-gray-500 dark:text-gray-400">
                        {scope_identifier(subscription)}
                      </span>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <.status_badge variant={status_variant(subscription.status)}>
                      {subscription.status || "unknown"}
                    </.status_badge>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="flex flex-col">
                      <span class="text-gray-900 dark:text-white">
                        {format_date(subscription.current_period_start)}
                      </span>
                      <span class="text-xs text-gray-500 dark:text-gray-400">
                        to {format_date(subscription.current_period_end)}
                      </span>
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell>
                    <div class="font-mono text-xs text-gray-700 dark:text-slate-300">
                      {subscription.stripe_price_id || "N/A"}
                    </div>
                  </.admin_table_cell>
                  <.admin_table_cell actions>
                    <.table_action_button
                      variant="primary"
                      phx_click="refresh_entitlement"
                      phx_value_id={subscription.id}
                    >
                      Refresh Entitlement
                    </.table_action_button>
                  </.admin_table_cell>
                </tr>
              <% end %>
            </:rows>
          </.admin_table_full>
        </.admin_table_container>

        <.admin_pagination
          pagination={@pagination}
          path={~p"/admin/billing"}
          params={list_params(@query, @scope, @pagination.page)}
        />
      </:body>
    </.admin_table>

    <.app_modal
      :if={@live_action == :show}
      id="subscription-details-modal"
      show
      on_cancel={JS.patch(~p"/admin/billing?#{list_params(@query, @scope, @pagination.page)}")}
      size="lg"
    >
      <:title>Subscription Details</:title>
      <:body>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <dl class="divide-y divide-gray-200 dark:divide-slate-600">
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {(@subscription.organization && @subscription.organization.name) || "Unknown"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Scope</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@subscription.scope_type} ({scope_identifier(@subscription)})
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Status</dt>
              <dd class="mt-1 text-sm sm:col-span-2 sm:mt-0">
                <.status_badge variant={status_variant(@subscription.status)}>
                  {@subscription.status || "unknown"}
                </.status_badge>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Stripe Customer</dt>
              <dd class="mt-1 text-sm font-mono text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 break-all">
                {@subscription.stripe_customer_id || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Stripe Subscription</dt>
              <dd class="mt-1 text-sm font-mono text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 break-all">
                {@subscription.stripe_subscription_id}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Stripe Price</dt>
              <dd class="mt-1 text-sm font-mono text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 break-all">
                {@subscription.stripe_price_id || "N/A"}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Current Period</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_date(@subscription.current_period_start)} to {format_date(
                  @subscription.current_period_end
                )}
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Entitlement Lock</dt>
              <dd class="mt-1 text-sm text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                <%= if @entitlement do %>
                  <%= if @entitlement.billing_locked do %>
                    Locked ({@entitlement.lock_reason || "unknown reason"})
                  <% else %>
                    Unlocked
                  <% end %>
                <% else %>
                  Missing entitlement row
                <% end %>
              </dd>
            </div>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Metadata</dt>
              <dd class="mt-1 text-xs font-mono text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                <pre class="overflow-x-auto rounded-md bg-gray-50 dark:bg-slate-900 p-3">{Jason.encode!(@subscription.metadata || %{}, pretty: true)}</pre>
              </dd>
            </div>
          </dl>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp list_subscriptions(query, scope, page) do
    query
    |> Billing.admin_subscriptions_query(scope)
    |> Pagination.paginate(page, @page_size)
  end

  defp normalize_scope(scope) when scope in ["all", "app", "project"], do: scope
  defp normalize_scope(_), do: "all"

  defp list_params(query, scope, page) do
    params = Pagination.list_params(query, page)

    case scope do
      "all" -> params
      _ -> Keyword.put(params, :scope, scope)
    end
  end

  defp status_variant(status) when status in ["active", "trialing"], do: "success"
  defp status_variant(status) when status in ["past_due", "unpaid"], do: "warning"

  defp status_variant(status)
       when status in ["canceled", "incomplete", "incomplete_expired", "paused"],
       do: "error"

  defp status_variant(_), do: "default"

  defp scope_identifier(%Subscription{scope_type: "app"}), do: "organization"
  defp scope_identifier(%Subscription{scope_id: nil}), do: "none"
  defp scope_identifier(%Subscription{scope_id: scope_id}), do: scope_id

  defp format_date(nil), do: "N/A"
  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp format_reason(reason) when is_atom(reason),
    do: reason |> Atom.to_string() |> String.replace("_", " ")

  defp format_reason(reason), do: inspect(reason)
end
