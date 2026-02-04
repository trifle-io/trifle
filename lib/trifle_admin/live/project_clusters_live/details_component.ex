defmodule TrifleAdmin.ProjectClustersLive.DetailsComponent do
  use TrifleAdmin, :live_component

  alias Trifle.Organizations

  @impl true
  def update(%{project_cluster: cluster} = assigns, socket) do
    accesses = Organizations.list_project_cluster_accesses(cluster)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:accesses, accesses)
     |> assign_new(:org_identifier, fn -> "" end)}
  end

  @impl true
  def handle_event("grant_access", %{"org_identifier" => identifier}, socket) do
    identifier = identifier |> to_string() |> String.trim()

    case find_organization(identifier) do
      nil ->
        {:noreply, put_flash(socket, :error, "Organization not found")}

      organization ->
        case Organizations.grant_project_cluster_access(
               socket.assigns.project_cluster,
               organization
             ) do
          {:ok, _access} ->
            accesses = Organizations.list_project_cluster_accesses(socket.assigns.project_cluster)

            {:noreply,
             socket
             |> put_flash(:info, "Access granted")
             |> assign(:accesses, accesses)
             |> assign(:org_identifier, "")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Access already exists")}
        end
    end
  end

  @impl true
  def handle_event("revoke_access", %{"id" => access_id}, socket) do
    access = Enum.find(socket.assigns.accesses, fn a -> to_string(a.id) == access_id end)

    case access do
      nil ->
        {:noreply, socket}

      access ->
        _ = Organizations.revoke_project_cluster_access(access)
        accesses = Organizations.list_project_cluster_accesses(socket.assigns.project_cluster)

        {:noreply,
         socket
         |> put_flash(:info, "Access revoked")
         |> assign(:accesses, accesses)}
    end
  end

  @impl true
  def handle_event("check_status", _params, socket) do
    case Organizations.check_project_cluster_status(socket.assigns.project_cluster) do
      {:ok, updated_cluster, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Status check completed successfully")
         |> assign(:project_cluster, updated_cluster)}

      {:error, updated_cluster, error_msg} ->
        {:noreply,
         socket
         |> put_flash(:error, "Status check failed: #{error_msg}")
         |> assign(:project_cluster, updated_cluster)}
    end
  end

  @impl true
  def handle_event("setup_cluster", _params, socket) do
    cluster = socket.assigns.project_cluster

    case Organizations.setup_project_cluster(cluster) do
      {:ok, message} ->
        {:ok, updated_cluster, _} = Organizations.check_project_cluster_status(cluster)

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(:project_cluster, updated_cluster)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Setup failed: #{error}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="pb-6">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-base/7 font-semibold text-gray-900 dark:text-white">
              {@project_cluster.name}
            </h3>
            <p class="mt-1 max-w-2xl text-sm/6 text-gray-500 dark:text-slate-400">
              {String.capitalize(@project_cluster.driver)} cluster · {@project_cluster.code}
            </p>
          </div>
          <div class="flex items-center gap-2">
            <%= if @project_cluster.is_default do %>
              <.status_badge variant="info">Default</.status_badge>
            <% end %>
            <%= if @project_cluster.status == "active" do %>
              <.status_badge variant="success">Active</.status_badge>
            <% else %>
              <.status_badge variant="pending">Coming soon</.status_badge>
            <% end %>
            <.status_badge variant={connection_badge_variant(@project_cluster.last_check_status)}>
              {connection_badge_text(@project_cluster.last_check_status)}
            </.status_badge>
          </div>
        </div>
      </div>

      <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
        <dl class="divide-y divide-gray-200 dark:divide-slate-600">
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Visibility</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
              {String.capitalize(@project_cluster.visibility)}
            </dd>
          </div>
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Location</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
              {format_location(@project_cluster)}
            </dd>
          </div>
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Host</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono">
              {format_host(@project_cluster)}
            </dd>
          </div>
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Database</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
              {@project_cluster.database_name || "N/A"}
            </dd>
          </div>
          <%= if @project_cluster.username do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Username</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@project_cluster.username}
              </dd>
            </div>
          <% end %>
          <%= if @project_cluster.auth_database do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Auth Database</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@project_cluster.auth_database}
              </dd>
            </div>
          <% end %>
          <%= if @project_cluster.last_check_at do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Last checked</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_timestamp(@project_cluster.last_check_at)}
              </dd>
            </div>
          <% end %>

          <%= for {key, value} <- (@project_cluster.config || %{}) do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">
                {humanize_config_key(key)}
              </dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_config_value(value)}
              </dd>
            </div>
          <% end %>
        </dl>
      </div>

      <div class="border-t border-gray-200 dark:border-slate-600 pt-6 mt-6">
        <h4 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">Connection actions</h4>
        <div class="flex flex-wrap items-center gap-3">
          <button
            type="button"
            phx-target={@myself}
            phx-click="check_status"
            class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
          >
            Check status
          </button>
          <button
            type="button"
            phx-target={@myself}
            phx-click="setup_cluster"
            class="inline-flex items-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
          >
            Setup cluster
          </button>
        </div>
      </div>

      <%= if @project_cluster.last_error do %>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6 mt-6">
          <div class="rounded-md bg-red-50 dark:bg-red-900/20 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg
                  class="h-5 w-5 text-red-400"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Connection Error</h3>
                <div class="mt-2 text-sm text-red-700">
                  <p>{@project_cluster.last_error}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <div class="border-t border-gray-200 dark:border-slate-600 pt-6 mt-6">
        <h4 class="text-sm font-semibold text-gray-900 dark:text-white mb-3">
          Allowed Organizations
        </h4>

        <%= if @project_cluster.visibility == "public" do %>
          <p class="text-sm text-gray-500 dark:text-slate-400">
            Public clusters are available to all organizations.
          </p>
        <% else %>
          <.form
            for={%{}}
            as={:access}
            phx-target={@myself}
            phx-submit="grant_access"
            class="flex flex-col sm:flex-row gap-2 mb-4"
          >
            <input
              type="text"
              name="org_identifier"
              value={@org_identifier}
              placeholder="Organization slug or ID"
              class="flex-1 rounded-md border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 px-3 py-2 text-sm text-gray-900 dark:text-white"
            />
            <button
              type="submit"
              class="inline-flex items-center justify-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
            >
              Grant access
            </button>
          </.form>

          <div class="space-y-2">
            <%= if Enum.empty?(@accesses) do %>
              <p class="text-sm text-gray-500 dark:text-slate-400">
                No organizations have access yet.
              </p>
            <% else %>
              <%= for access <- @accesses do %>
                <div class="flex items-center justify-between rounded-md border border-gray-200 dark:border-slate-600 px-3 py-2">
                  <div class="text-sm text-gray-700 dark:text-slate-300">
                    {access.organization && access.organization.name}
                  </div>
                  <button
                    type="button"
                    phx-click="revoke_access"
                    phx-target={@myself}
                    phx-value-id={access.id}
                    class="text-xs font-medium text-red-600 hover:text-red-700"
                  >
                    Remove
                  </button>
                </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp find_organization(identifier) do
    case identifier do
      "" ->
        nil

      _ ->
        Organizations.get_organization_by_slug(identifier) ||
          Organizations.get_organization(identifier)
    end
  end

  defp format_location(cluster) do
    [cluster.region, cluster.city, cluster.country]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
    |> case do
      "" -> "Not set"
      value -> value
    end
  end

  defp format_host(cluster) do
    case cluster.host do
      nil ->
        "Not set"

      "" ->
        "Not set"

      host when is_binary(host) ->
        if cluster.port, do: "#{host}:#{cluster.port}", else: host
    end
  end

  defp humanize_config_key(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_config_value(nil), do: "Not set"
  defp format_config_value(true), do: "Enabled"
  defp format_config_value(false), do: "Disabled"
  defp format_config_value(value) when is_binary(value), do: value
  defp format_config_value(value), do: to_string(value)

  defp connection_badge_variant("success"), do: "success"
  defp connection_badge_variant("error"), do: "error"
  defp connection_badge_variant("pending"), do: "pending"
  defp connection_badge_variant(_), do: "warning"

  defp connection_badge_text("success"), do: "Connected"
  defp connection_badge_text("error"), do: "Error"
  defp connection_badge_text("pending"), do: "Pending"
  defp connection_badge_text(_), do: "Unknown"

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(%DateTime{} = timestamp) do
    Calendar.strftime(timestamp, "%B %d, %Y at %I:%M %p UTC")
  end

  defp format_timestamp(%NaiveDateTime{} = timestamp) do
    Calendar.strftime(timestamp, "%B %d, %Y at %I:%M %p UTC")
  end
end
