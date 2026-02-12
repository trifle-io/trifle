defmodule TrifleApp.OrganizationBillingLive do
  use TrifleApp, :live_view

  alias Trifle.Billing
  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Billing")
      |> assign(:breadcrumb_links, Navigation.breadcrumb(:billing))
      |> assign(:active_tab, :billing)
      |> assign(:deployment_mode, deployment_mode())
      |> assign(:show_plans_modal, false)
      |> assign(:plans_interval, "month")
      |> assign(:billing_snapshot, nil)

    cond do
      is_nil(socket.assigns[:current_user]) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization/profile")}

      true ->
        {:ok,
         socket
         |> assign(:current_membership, membership)
         |> assign(:billing_snapshot, billing_snapshot_for(membership))}
    end
  end

  def handle_event("show_plans", _params, socket) do
    {:noreply, assign(socket, :show_plans_modal, true)}
  end

  def handle_event("hide_plans", _params, socket) do
    {:noreply, assign(socket, :show_plans_modal, false)}
  end

  def handle_event("set_plans_interval", %{"interval" => interval}, socket)
      when interval in ["month", "year"] do
    {:noreply, assign(socket, :plans_interval, interval)}
  end

  def handle_event("set_plans_interval", %{"interval" => _other}, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8 space-y-6">
      <Navigation.nav active_tab={@active_tab} />

      <%= if @deployment_mode == :self_hosted do %>
        <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-6">
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Billing & Subscription</h2>
          <p class="mt-2 text-sm text-gray-600 dark:text-slate-300">
            You are running the self-hosted edition. SaaS billing is disabled in this mode.
          </p>
        </div>
      <% else %>
        <%= if @billing_snapshot do %>
          <%= if app = @billing_snapshot.app_subscription do %>
            <.subscription_details
              subscription={app}
              plan={@billing_snapshot.app_plan}
              entitlement={@billing_snapshot.entitlement}
              seats_used={@billing_snapshot.seats_used}
            />
          <% else %>
            <.no_subscription />
          <% end %>

          <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-6">
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Project Plans</h2>
            <p class="mt-1 text-sm text-gray-600 dark:text-slate-300">
              Review per-project usage and manage project data plans.
            </p>

            <div class="mt-4 divide-y divide-gray-200 dark:divide-slate-700">
              <%= for entry <- @billing_snapshot.projects do %>
                <div class="py-3 flex items-center justify-between gap-3">
                  <div>
                    <p class="text-sm font-medium text-gray-900 dark:text-white">
                      {entry.project.name}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-slate-400">
                      Usage: {(entry.usage && entry.usage.events_count) || 0}
                    </p>
                  </div>
                  <.link
                    navigate={~p"/projects/#{entry.project.id}/billing"}
                    class="inline-flex items-center rounded-md border border-gray-300 dark:border-slate-600 px-3 py-2 text-sm text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
                  >
                    Manage
                  </.link>
                </div>
              <% end %>
            </div>
          </div>

          <.app_plans_modal
            show={@show_plans_modal}
            tiers={@billing_snapshot.available_app_tiers}
            current_tier={current_app_tier(@billing_snapshot)}
            current_interval={current_app_interval(@billing_snapshot)}
            selected_interval={@plans_interval}
          />
        <% else %>
          <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-6">
            <p class="text-sm text-gray-600 dark:text-slate-300">Billing data is not available.</p>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp no_subscription(assigns) do
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
            d="M2.25 8.25h19.5M2.25 9h19.5m-16.5 5.25h6m-6 2.25h3m-3.75 3h15a2.25 2.25 0 0 0 2.25-2.25V6.75A2.25 2.25 0 0 0 19.5 4.5h-15a2.25 2.25 0 0 0-2.25 2.25v10.5A2.25 2.25 0 0 0 4.5 19.5Z"
          />
        </svg>
      </div>
      <h2 class="mt-4 text-lg font-semibold text-gray-900 dark:text-white">No active subscription</h2>
      <p class="mt-2 text-sm text-gray-600 dark:text-slate-300">
        Subscribe to a plan to unlock all features for your organization.
      </p>
      <button
        phx-click="show_plans"
        class="mt-4 inline-flex items-center rounded-md bg-teal-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-teal-700 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2"
      >
        Subscribe
      </button>
    </div>
    """
  end

  defp subscription_details(assigns) do
    assigns =
      assigns
      |> assign(:status_color, status_color(assigns.subscription.status))
      |> assign(:plan_name, plan_display_name(assigns.plan))
      |> assign(:plan_price, plan_display_price(assigns.plan))
      |> assign(:interval_label, interval_label(assigns.subscription.interval))

    ~H"""
    <div class="rounded-lg border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 p-6">
      <div class="flex items-start justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">App Subscription</h2>
          <p class="mt-1 text-sm text-gray-600 dark:text-slate-300">
            Manage your organization plan and billing.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <form action={~p"/organization/billing/portal"} method="post">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <button class="inline-flex items-center rounded-md bg-gray-100 dark:bg-slate-700 px-3 py-2 text-sm font-medium text-gray-700 dark:text-slate-200 hover:bg-gray-200 dark:hover:bg-slate-600">
              Billing Portal
            </button>
          </form>
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
            Plan
          </dt>
          <dd class="mt-1 flex items-center gap-2">
            <span class="text-sm font-semibold text-gray-900 dark:text-white">{@plan_name}</span>
            <%= if @subscription.founder_price do %>
              <span class="inline-flex items-center rounded-full bg-amber-100 dark:bg-amber-900/30 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-300">
                Founder
              </span>
            <% end %>
          </dd>
        </div>

        <div>
          <dt class="text-xs font-medium text-gray-500 dark:text-slate-400 uppercase tracking-wide">
            Price
          </dt>
          <dd class="mt-1 text-sm font-semibold text-gray-900 dark:text-white">
            {@plan_price}<span class="text-xs font-normal text-gray-500 dark:text-slate-400">/{@interval_label}</span>
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
            Seats
          </dt>
          <dd class="mt-1 text-sm text-gray-900 dark:text-white">
            <span class="font-semibold">{@seats_used}</span>
            <%= if seat_limit = @entitlement && @entitlement.seat_limit do %>
              <span class="text-gray-500 dark:text-slate-400">/ {seat_limit}</span>
            <% end %>
          </dd>
        </div>
      </div>

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

      <%= if @subscription.cancel_at_period_end do %>
        <div class="mt-3 rounded-md bg-amber-50 dark:bg-amber-900/20 p-3">
          <p class="text-sm text-amber-700 dark:text-amber-300">
            Your subscription will cancel at the end of the current billing period.
          </p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :tiers, :list, required: true
  attr :current_tier, :string, default: nil
  attr :current_interval, :string, default: nil
  attr :selected_interval, :string, required: true

  defp app_plans_modal(assigns) do
    assigns =
      assign(
        assigns,
        :filtered_tiers,
        Enum.filter(assigns.tiers, fn tier -> tier.interval == assigns.selected_interval end)
      )

    ~H"""
    <.app_modal id="app-plans-modal" show={@show} on_cancel="hide_plans" size="lg">
      <:title>Choose a Plan</:title>
      <:body>
        <%!-- Monthly / Yearly toggle --%>
        <div class="flex items-center justify-center mt-1 mb-6">
          <div class="inline-flex items-center rounded-full bg-gray-100 dark:bg-slate-700 p-1">
            <button
              phx-click="set_plans_interval"
              phx-value-interval="month"
              class={[
                "rounded-full px-4 py-1.5 text-sm font-medium transition-colors",
                if(@selected_interval == "month",
                  do: "bg-white dark:bg-slate-600 text-gray-900 dark:text-white shadow-sm",
                  else:
                    "text-gray-500 dark:text-slate-400 hover:text-gray-700 dark:hover:text-slate-300"
                )
              ]}
            >
              Monthly
            </button>
            <button
              phx-click="set_plans_interval"
              phx-value-interval="year"
              class={[
                "rounded-full px-4 py-1.5 text-sm font-medium transition-colors",
                if(@selected_interval == "year",
                  do: "bg-white dark:bg-slate-600 text-gray-900 dark:text-white shadow-sm",
                  else:
                    "text-gray-500 dark:text-slate-400 hover:text-gray-700 dark:hover:text-slate-300"
                )
              ]}
            >
              Yearly
            </button>
            <span class="ml-2 mr-1 inline-flex items-center rounded-full bg-teal-100 dark:bg-teal-900/30 px-2 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-300">
              Save 15%
            </span>
          </div>
        </div>

        <%!-- Plan cards --%>
        <div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <%= for tier <- @filtered_tiers do %>
            <% is_current = @current_tier == tier.tier && @current_interval == tier.interval %>
            <% is_popular = tier.tier == "team" %>
            <div class={[
              "rounded-lg border p-5 flex flex-col relative",
              cond do
                is_popular ->
                  "border-teal-500 dark:border-teal-400 border-2"

                is_current ->
                  "border-teal-500 dark:border-teal-400 ring-1 ring-teal-500 dark:ring-teal-400"

                true ->
                  "border-gray-200 dark:border-slate-700"
              end
            ]}>
              <%= if is_popular do %>
                <div class="absolute -top-3 left-1/2 -translate-x-1/2">
                  <span class="inline-flex items-center rounded-full bg-teal-500 px-3 py-0.5 text-xs font-semibold text-white">
                    Popular
                  </span>
                </div>
              <% end %>

              <div class="flex items-center justify-between">
                <h3 class="text-base font-semibold text-gray-900 dark:text-white">
                  {String.capitalize(tier.tier)}
                </h3>
                <%= if is_current do %>
                  <span class="inline-flex items-center rounded-full bg-teal-100 dark:bg-teal-900/30 px-2 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-300">
                    Current
                  </span>
                <% end %>
              </div>

              <div class="mt-3">
                <span class="text-3xl font-bold text-gray-900 dark:text-white">{tier.amount}</span>
                <span class="text-sm text-gray-500 dark:text-slate-400">
                  /{interval_label(tier.interval)}
                </span>
              </div>

              <%= if founder = tier[:founder_offer] do %>
                <p class="mt-2 text-xs text-teal-600 dark:text-teal-300">
                  Founder offer: {founder_offer_label(founder)}
                </p>
              <% end %>

              <%!-- Feature list --%>
              <ul class="mt-4 space-y-2.5 text-sm text-gray-600 dark:text-slate-300 flex-1">
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>{tier_user_label(tier)}</span>
                </li>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>Unlimited databases</span>
                </li>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>Dashboards & alerts</span>
                </li>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>Projects</span>
                </li>
                <li class="flex items-start gap-2">
                  <.check_icon />
                  <span>AI features</span>
                </li>
              </ul>

              <div class="mt-5">
                <%= if is_current do %>
                  <button
                    disabled
                    class="w-full inline-flex justify-center rounded-md bg-gray-100 dark:bg-slate-700 px-3 py-2 text-sm font-medium text-gray-400 dark:text-slate-500 cursor-not-allowed"
                  >
                    Current Plan
                  </button>
                <% else %>
                  <form action={~p"/organization/billing/checkout/app"} method="post">
                    <input
                      type="hidden"
                      name="_csrf_token"
                      value={Phoenix.Controller.get_csrf_token()}
                    />
                    <input type="hidden" name="tier" value={tier.tier} />
                    <input type="hidden" name="interval" value={tier.interval} />
                    <button class={[
                      "w-full inline-flex justify-center rounded-md px-3 py-2 text-sm font-medium",
                      if(is_popular,
                        do: "bg-teal-600 text-white hover:bg-teal-700",
                        else:
                          "border border-gray-300 dark:border-slate-600 text-gray-700 dark:text-slate-200 hover:bg-gray-50 dark:hover:bg-slate-700"
                      )
                    ]}>
                      Get Started
                    </button>
                  </form>
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

  defp billing_snapshot_for(nil), do: nil
  defp billing_snapshot_for(membership), do: Billing.billing_snapshot_for_membership(membership)

  defp current_app_tier(%{app_plan: %Billing.Plan{tier_key: tier}}), do: tier
  defp current_app_tier(_), do: nil

  defp current_app_interval(%{app_subscription: %Billing.Subscription{interval: interval}}),
    do: interval

  defp current_app_interval(_), do: nil

  defp plan_display_name(%Billing.Plan{tier_key: tier}), do: String.capitalize(tier)
  defp plan_display_name(_), do: "Unknown"

  defp plan_display_price(%Billing.Plan{amount_cents: cents, currency: currency}),
    do: Billing.format_amount(cents, currency)

  defp plan_display_price(_), do: "—"

  defp interval_label("month"), do: "mo"
  defp interval_label("year"), do: "yr"
  defp interval_label(other) when is_binary(other), do: other
  defp interval_label(_), do: "mo"

  defp tier_user_label(%{seat_limit: limit}) when is_integer(limit) and limit > 100,
    do: "Unlimited users"

  defp tier_user_label(%{seat_limit: limit}) when is_integer(limit),
    do: "#{limit} users"

  defp tier_user_label(_), do: "1 user"

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

  defp founder_offer_label(%{amount: amount, status: status})
       when is_binary(amount) and is_binary(status) do
    "#{amount} · #{String.replace(status, "_", " ")}"
  end

  defp founder_offer_label(%{amount: amount}) when is_binary(amount), do: amount

  defp founder_offer_label(%{status: status}) when is_binary(status),
    do: String.replace(status, "_", " ")

  defp founder_offer_label(_), do: "available"

  defp deployment_mode do
    Application.get_env(:trifle, :deployment_mode, :saas)
  end
end
