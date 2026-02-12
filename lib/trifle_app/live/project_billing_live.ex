defmodule TrifleApp.ProjectBillingLive do
  use TrifleApp, :live_view

  alias Trifle.Billing
  alias Trifle.Organizations
  alias Trifle.Organizations.Project

  def mount(%{"id" => id}, _session, socket) do
    membership = socket.assigns[:current_membership]

    cond do
      is_nil(socket.assigns[:current_user]) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok,
         socket
         |> put_flash(:error, "Organization membership is required.")
         |> push_navigate(to: ~p"/organization/billing")}

      true ->
        case fetch_state(membership, id) do
          {:ok, state} ->
            {:ok,
             socket
             |> assign(:page_title, "Projects · #{state.project.name} · Billing")
             |> assign(:nav_section, :projects)
             |> assign(:breadcrumb_links, project_breadcrumb_links(state.project, "Billing"))
             |> assign(:state, state)
             |> assign(:show_plans_modal, false)}

          {:error, :not_found} ->
            {:ok,
             socket
             |> put_flash(:error, "Project not found.")
             |> push_navigate(to: ~p"/organization/billing")}
        end
    end
  end

  def handle_event("show_plans", _params, socket) do
    {:noreply, assign(socket, :show_plans_modal, true)}
  end

  def handle_event("hide_plans", _params, socket) do
    {:noreply, assign(socket, :show_plans_modal, false)}
  end

  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="sm:p-4">
        <.project_nav project={@state.project} current={:billing} />
      </div>

      <div class="px-4 sm:px-6 lg:px-8 space-y-6">
        <%= if @state.subscription && @state.subscription.status in ["active", "trialing", "past_due"] do %>
          <.project_subscription_details
            project={@state.project}
            subscription={@state.subscription}
            plan={@state.plan}
            usage={@state.usage}
          />
        <% else %>
          <.no_project_subscription project={@state.project} />
        <% end %>
      </div>

      <.project_plans_modal
        show={@show_plans_modal}
        project={@state.project}
        tiers={@state.available_project_tiers}
        current_tier={current_project_tier(@state)}
      />
    </div>
    """
  end

  defp no_project_subscription(assigns) do
    ~H"""
    <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-6 text-center">
      <div class="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-gray-100 dark:bg-slate-700">
        <svg
          class="h-6 w-6 text-gray-400 dark:text-slate-500"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694-4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12 18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125"
          />
        </svg>
      </div>
      <h2 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">{@project.name}</h2>
      <p class="mt-2 text-sm text-gray-600 dark:text-slate-300">
        No active data plan. Choose a plan to start ingesting events.
      </p>
      <div class="mt-4 flex items-center justify-center gap-3">
        <button
          phx-click="show_plans"
          class="inline-flex items-center rounded-md bg-teal-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-teal-700 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2"
        >
          Choose a Plan
        </button>
        <.link
          navigate={~p"/organization/billing"}
          class="inline-flex items-center text-sm text-gray-500 dark:text-slate-400 hover:text-gray-700 dark:hover:text-slate-300"
        >
          Back to Organization Billing
        </.link>
      </div>
    </div>
    """
  end

  defp project_subscription_details(assigns) do
    assigns =
      assigns
      |> assign(:status_color, status_color(assigns.subscription.status))
      |> assign(:tier_name, tier_display_name(assigns.plan, assigns.usage))
      |> assign(:plan_price, plan_display_price(assigns.plan))
      |> assign(:events_count, (assigns.usage && assigns.usage.events_count) || 0)
      |> assign(:hard_limit, assigns.usage && assigns.usage.hard_limit)

    ~H"""
    <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">{@project.name}</h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-slate-300">
            Project data plan and usage.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <.link
            navigate={~p"/organization/billing"}
            class="inline-flex items-center rounded-md bg-gray-100 dark:bg-slate-700 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-200 dark:hover:bg-slate-600"
          >
            Organization Billing
          </.link>
          <button
            phx-click="show_plans"
            class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-medium text-white hover:bg-teal-700"
          >
            Change Plan
          </button>
        </div>
      </div>

      <div class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <dt class="text-xs font-medium text-gray-500 dark:text-slate-400 uppercase tracking-wide">
            Tier
          </dt>
          <dd class="mt-1 text-sm font-semibold text-gray-900 dark:text-white">{@tier_name}</dd>
        </div>

        <div>
          <dt class="text-xs font-medium text-gray-500 dark:text-slate-400 uppercase tracking-wide">
            Price
          </dt>
          <dd class="mt-1 text-sm font-semibold text-gray-900 dark:text-white">
            {@plan_price}<span class="text-xs font-normal text-gray-500 dark:text-slate-400">/mo</span>
          </dd>
        </div>

        <div>
          <dt class="text-xs font-medium text-gray-500 dark:text-slate-400 uppercase tracking-wide">
            Status
          </dt>
          <dd class="mt-1">
            <span class={"inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium #{@status_color}"}>
              {String.replace(@subscription.status || "unknown", "_", " ")}
            </span>
          </dd>
        </div>

        <div>
          <dt class="text-xs font-medium text-gray-500 dark:text-slate-400 uppercase tracking-wide">
            Events
          </dt>
          <dd class="mt-1 text-sm text-gray-900 dark:text-white">
            <span class="font-semibold">{format_number(@events_count)}</span>
            <%= if @hard_limit do %>
              <span class="text-gray-500 dark:text-slate-400">/ {format_number(@hard_limit)}</span>
            <% end %>
          </dd>
        </div>
      </div>

      <%= if @hard_limit && @hard_limit > 0 do %>
        <div class="mt-4">
          <div class="flex items-center justify-between text-xs text-gray-500 dark:text-slate-400 mb-1">
            <span>Usage</span>
            <span>{usage_percentage(@events_count, @hard_limit)}%</span>
          </div>
          <div class="w-full bg-gray-200 dark:bg-slate-700 rounded-full h-2">
            <div
              class={[
                "h-2 rounded-full",
                if(usage_percentage(@events_count, @hard_limit) > 90,
                  do: "bg-red-500",
                  else: "bg-teal-500"
                )
              ]}
              style={"width: #{min(usage_percentage(@events_count, @hard_limit), 100)}%"}
            >
            </div>
          </div>
        </div>
      <% end %>

      <%= if @subscription.current_period_start || @subscription.current_period_end do %>
        <div class="mt-4 pt-4 border-t border-gray-100 dark:border-slate-700">
          <p class="text-xs text-gray-500 dark:text-slate-400">
            Current period:
            <span class="font-medium text-gray-700 dark:text-slate-300">
              {format_date(@subscription.current_period_start)} — {format_date(
                @subscription.current_period_end
              )}
            </span>
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :project, Project, required: true
  attr :tiers, :list, required: true
  attr :current_tier, :string, default: nil

  defp project_plans_modal(assigns) do
    ~H"""
    <.app_modal id="project-plans-modal" show={@show} on_cancel="hide_plans" size="lg">
      <:title>Choose a Data Plan</:title>
      <:body>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 mt-2">
          <%= for tier <- @tiers do %>
            <% is_current = @current_tier == tier.tier_key %>
            <div class={[
              "rounded-lg border p-5 flex flex-col",
              if(is_current,
                do: "border-teal-500 dark:border-teal-400 ring-1 ring-teal-500 dark:ring-teal-400",
                else: "border-gray-200 dark:border-slate-700"
              )
            ]}>
              <div class="flex items-center justify-between">
                <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                  {String.upcase(tier.tier_key)}
                </h3>
                <%= if is_current do %>
                  <span class="inline-flex items-center rounded-full bg-teal-100 dark:bg-teal-900/30 px-2 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-300">
                    Current
                  </span>
                <% end %>
              </div>

              <div class="mt-3">
                <span class="text-3xl font-bold text-gray-900 dark:text-white">{tier.amount}</span>
                <span class="text-sm text-gray-500 dark:text-slate-400">/mo</span>
              </div>

              <%!-- Feature list --%>
              <ul class="mt-4 space-y-2.5 text-sm text-gray-600 dark:text-slate-300 flex-1">
                <%= if limit = tier[:hard_limit] do %>
                  <li class="flex items-start gap-2">
                    <.check_icon />
                    <span>Up to {format_number(limit)} events/mo</span>
                  </li>
                <% end %>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>Unlimited keys</span>
                </li>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>Auto-aggregation</span>
                </li>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>REST API access</span>
                </li>
              </ul>

              <div class="mt-5 space-y-2">
                <%= if is_current do %>
                  <button
                    disabled
                    class="w-full inline-flex justify-center rounded-md bg-gray-100 dark:bg-slate-700 px-3 py-2 text-sm font-medium text-gray-400 dark:text-slate-500 cursor-not-allowed"
                  >
                    Current Plan
                  </button>
                <% else %>
                  <form
                    action={~p"/organization/billing/checkout/project/#{@project.id}"}
                    method="post"
                  >
                    <input
                      type="hidden"
                      name="_csrf_token"
                      value={Phoenix.Controller.get_csrf_token()}
                    />
                    <input type="hidden" name="tier" value={tier.tier_key} />
                    <input type="hidden" name="retention" value="false" />
                    <button class="w-full inline-flex justify-center rounded-md bg-teal-600 px-3 py-2 text-sm font-medium text-white hover:bg-teal-700">
                      Choose Tier
                    </button>
                  </form>

                  <%= if tier[:retention_available] do %>
                    <form
                      action={~p"/organization/billing/checkout/project/#{@project.id}"}
                      method="post"
                    >
                      <input
                        type="hidden"
                        name="_csrf_token"
                        value={Phoenix.Controller.get_csrf_token()}
                      />
                      <input type="hidden" name="tier" value={tier.tier_key} />
                      <input type="hidden" name="retention" value="true" />
                      <button class="w-full inline-flex justify-center rounded-md border border-gray-300 dark:border-slate-600 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700">
                        + Retention
                        <%= if amount = tier[:retention_amount] do %>
                          ({amount})
                        <% end %>
                      </button>
                    </form>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </:body>
    </.app_modal>
    """
  end

  defp check_icon(assigns) do
    ~H"""
    <svg
      class="h-4 w-4 mt-0.5 shrink-0 text-teal-500"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="2"
      stroke="currentColor"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5" />
    </svg>
    """
  end

  defp fetch_state(membership, project_id) do
    project = Organizations.get_project_for_org!(membership.organization_id, project_id)
    snapshot = Billing.billing_snapshot_for_membership(membership)

    entry = Enum.find(snapshot.projects, fn item -> item.project.id == project.id end)

    {:ok,
     %{
       project: project,
       usage: entry && entry.usage,
       subscription: entry && entry.subscription,
       plan: entry && entry.plan,
       available_project_tiers: snapshot.available_project_tiers
     }}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp current_project_tier(%{plan: %Billing.Plan{tier_key: tier}}), do: tier
  defp current_project_tier(%{usage: %{tier_key: tier}}) when is_binary(tier), do: tier
  defp current_project_tier(_), do: nil

  defp tier_display_name(%Billing.Plan{tier_key: tier}, _usage), do: String.upcase(tier)
  defp tier_display_name(_, %{tier_key: tier}) when is_binary(tier), do: String.upcase(tier)
  defp tier_display_name(_, _), do: "—"

  defp plan_display_price(%Billing.Plan{amount_cents: cents, currency: currency}),
    do: Billing.format_amount(cents, currency)

  defp plan_display_price(_), do: "—"

  defp status_color("active"),
    do: "bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300"

  defp status_color("trialing"),
    do: "bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300"

  defp status_color("past_due"),
    do: "bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300"

  defp status_color("canceled"),
    do: "bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300"

  defp status_color("unpaid"), do: "bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300"
  defp status_color(_), do: "bg-gray-100 dark:bg-gray-900/30 text-gray-700 dark:text-gray-300"

  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y")
  defp format_date(_), do: "—"

  defp format_number(n) when is_integer(n) and n >= 1_000_000, do: "#{div(n, 1_000_000)}M"
  defp format_number(n) when is_integer(n) and n >= 1_000, do: "#{div(n, 1_000)}K"
  defp format_number(n) when is_integer(n), do: Integer.to_string(n)
  defp format_number(_), do: "0"

  defp usage_percentage(count, limit)
       when is_integer(count) and is_integer(limit) and limit > 0 do
    round(count / limit * 100)
  end

  defp usage_percentage(_, _), do: 0

  defp project_breadcrumb_links(%Project{} = project, last) do
    project_name = project.name || "Project"

    [
      {"Projects", ~p"/projects"},
      {project_name, ~p"/projects/#{project.id}/transponders"},
      last
    ]
  end
end
