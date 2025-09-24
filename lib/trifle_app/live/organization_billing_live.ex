defmodule TrifleApp.OrganizationBillingLive do
  use TrifleApp, :live_view

  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Billing")
      |> assign(:active_tab, :billing)
      |> assign(:deployment_mode, deployment_mode())

    cond do
      is_nil(socket.assigns[:current_user]) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization")}

      true ->
        {:ok, assign(socket, :current_membership, membership)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <Navigation.nav active_tab={@active_tab} />
      <div class="bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg p-6">
        <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-2">
          Billing & Subscription
        </h2>
        <p class="text-sm text-gray-600 dark:text-slate-300">
          You're running the open-source edition of Trifle; That means no invoices! Just coffee and late hours.
        </p>
        <%= if @deployment_mode == :self_hosted do %>
          <p class="mt-4 text-sm text-gray-500 dark:text-slate-400">
            When licensing lands, this space will surface renewal details for self-hosted installs.
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  defp deployment_mode do
    Application.get_env(:trifle, :deployment_mode, :saas)
  end
end
