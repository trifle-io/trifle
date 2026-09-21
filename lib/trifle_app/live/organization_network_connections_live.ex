defmodule TrifleApp.OrganizationNetworkConnectionsLive do
  use TrifleApp, :live_view
  alias Trifle.Organizations
  alias Trifle.Organizations.NetworkConnections
  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    membership = socket.assigns[:current_membership]

    if membership do
      {:ok,
       socket
       |> assign(:page_title, "Organization · Connections")
       |> assign(
         :can_manage,
         Organizations.membership_owner?(membership) or
           Organizations.membership_admin?(membership)
       )
       |> assign(:busy, MapSet.new())
       |> assign(:form_revision, 0)
       |> assign(:error, nil)
       |> load()}
    else
      {:ok, push_navigate(socket, to: ~p"/organization/profile")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <Navigation.nav active_tab={:connections} />
      <h1 class="text-base font-semibold text-gray-900 dark:text-white">Network connections</h1>
      <p class="mt-2 text-sm text-gray-500 dark:text-slate-400">
        Connect Trifle to your Tailscale network to read private databases and trace storage.
      </p>
      <p
        :if={@error}
        role="alert"
        class="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800 dark:bg-red-900/20 dark:text-red-200"
      >
        {@error}
      </p>

      <section
        :if={@can_manage}
        class="mt-6 rounded-lg border border-slate-200 bg-white p-5 dark:border-slate-700 dark:bg-slate-800"
      >
        <h2 class="font-semibold text-gray-900 dark:text-white">Add a Tailscale connection</h2>
        <p class="mt-2 text-sm text-gray-600 dark:text-slate-300">
          In Tailscale, create a tagged auth key with ephemeral mode off. Grant that tag access to
          your database and storage ports, then paste the key here. Trifle enrolls a device in your tailnet.
        </p>
        <a
          href="https://tailscale.com/docs/features/access-control/auth-keys"
          target="_blank"
          rel="noopener noreferrer"
          class="mt-2 inline-block text-sm text-teal-700 underline dark:text-teal-300"
        >
          Tailscale auth-key instructions
        </a>
        <form id="network-connection-form" phx-submit="create" class="mt-4 grid gap-4 sm:grid-cols-2">
          <div id={"network-name-input-#{@form_revision}"}>
            <label for="network-name" class="block text-sm font-medium text-gray-900 dark:text-white">
              Name
            </label>
            <input
              id="network-name"
              name="connection[name]"
              required
              maxlength="160"
              placeholder="Production network"
              class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>
          <div id={"network-auth-input-#{@form_revision}"}>
            <label
              for="network-auth-key"
              class="block text-sm font-medium text-gray-900 dark:text-white"
            >
              Tailscale auth key
            </label>
            <input
              id="network-auth-key"
              name="connection[auth_key]"
              type="password"
              required
              autocomplete="new-password"
              placeholder="tskey-auth-…"
              class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-900 dark:text-white"
            />
          </div>
          <p class="text-xs text-gray-500 dark:text-slate-400 sm:col-span-2">
            Use an auth key, not an API access token. The enrollment key is cleared after the device connects.
          </p>
          <.primary_button type="submit" phx-disable-with="Adding…">Add connection</.primary_button>
        </form>
      </section>

      <p :if={@connections == []} class="mt-8 text-sm text-gray-500 dark:text-slate-400">
        No Tailscale connections yet.
      </p>
      <div class="mt-6 space-y-4">
        <article
          :for={connection <- @connections}
          id={"connection-#{connection.id}"}
          class="rounded-lg border border-slate-200 bg-white p-5 dark:border-slate-700 dark:bg-slate-800"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 class="font-semibold text-gray-900 dark:text-white">{connection.name}</h2>
              <p class="mt-1 text-sm text-gray-600 dark:text-slate-300">
                {status_label(connection.status)}
              </p>
              <p
                :if={connection.hostname}
                class="mt-1 break-all font-mono text-xs text-gray-500 dark:text-slate-400"
              >
                {connection.hostname}
              </p>
              <p class="mt-1 font-mono text-xs text-gray-500 dark:text-slate-400">
                {Enum.join(connection.addresses, ", ")}
              </p>
            </div>
            <div :if={@can_manage} class="flex flex-wrap gap-3 text-sm">
              <button
                phx-click="refresh"
                phx-value-id={connection.id}
                disabled={MapSet.member?(@busy, connection.id)}
                class="text-teal-700 disabled:opacity-50 dark:text-teal-300"
              >
                Refresh status
              </button>
              <button
                :if={connection.enabled}
                phx-click="disconnect"
                phx-value-id={connection.id}
                data-confirm="Disconnect this tailnet? Sources using it will stop working."
                disabled={MapSet.member?(@busy, connection.id)}
                class="text-gray-600 disabled:opacity-50 dark:text-slate-300"
              >
                Disconnect
              </button>
              <button
                phx-click="delete"
                phx-value-id={connection.id}
                data-confirm="Delete this connection? Remove its Trifle device from Tailscale afterward."
                disabled={MapSet.member?(@busy, connection.id)}
                class="text-red-700 disabled:opacity-50 dark:text-red-300"
              >
                Delete
              </button>
            </div>
          </div>
          <p
            :if={MapSet.member?(@busy, connection.id)}
            role="status"
            class="mt-3 text-sm text-gray-500"
          >
            Connecting…
          </p>
          <p
            :if={connection.last_error}
            role="alert"
            class="mt-3 text-sm text-red-700 dark:text-red-300"
          >
            {connection.last_error}
          </p>
          <p
            :if={connection.status == "approval_required"}
            class="mt-3 text-sm text-amber-700 dark:text-amber-300"
          >
            Approve this device in Tailscale, then refresh its status.
          </p>
          <details :if={@can_manage} class="mt-4 text-sm text-gray-600 dark:text-slate-300">
            <summary class="cursor-pointer">Reauthorize with a new auth key</summary>
            <form phx-submit="reauthorize" class="mt-3 flex flex-wrap gap-3">
              <input type="hidden" name="connection_id" value={connection.id} />
              <label class="sr-only" for={"auth-key-#{connection.id}-#{connection.generation}"}>
                New Tailscale auth key
              </label>
              <input
                id={"auth-key-#{connection.id}-#{connection.generation}"}
                type="password"
                name="auth_key"
                required
                autocomplete="new-password"
                placeholder="tskey-auth-…"
                class="min-w-0 flex-1 rounded-md border-gray-300 dark:border-slate-600 dark:bg-slate-900 dark:text-white"
              />
              <.primary_button type="submit" disabled={MapSet.member?(@busy, connection.id)}>
                Reauthorize
              </.primary_button>
            </form>
          </details>
          <p :if={!connection.enabled} class="mt-3 text-xs text-gray-500 dark:text-slate-400">
            Remove the old Trifle device from your Tailscale admin console. Reauthorizing enrolls a new device.
          </p>
        </article>
      </div>
    </div>
    """
  end

  def handle_event("create", %{"connection" => attrs}, socket) do
    if socket.assigns.can_manage do
      organization =
        Organizations.get_organization!(socket.assigns.current_membership.organization_id)

      case NetworkConnections.create(organization, attrs) do
        {:ok, connection} ->
          {:noreply,
           socket |> update(:form_revision, &(&1 + 1)) |> load() |> run(connection, :refresh)}

        {:error, changeset} ->
          {:noreply, assign(socket, :error, changeset_error(changeset))}
      end
    else
      {:noreply, forbidden(socket)}
    end
  end

  def handle_event("reauthorize", %{"connection_id" => id} = params, socket) do
    handle_event("reauthorize", Map.put(params, "id", id), socket)
  end

  def handle_event(action, %{"id" => id} = params, socket)
      when action in ["refresh", "disconnect", "delete", "reauthorize"] do
    with true <- socket.assigns.can_manage,
         false <- MapSet.member?(socket.assigns.busy, id),
         %{} = connection <-
           NetworkConnections.get(socket.assigns.current_membership.organization_id, id) do
      if action == "reauthorize" do
        case NetworkConnections.reauthorize(connection, params["auth_key"] || "") do
          {:ok, updated} -> {:noreply, socket |> load() |> run(updated, :refresh)}
          {:error, changeset} -> {:noreply, assign(socket, :error, changeset_error(changeset))}
        end
      else
        {:noreply, run(socket, connection, String.to_existing_atom(action))}
      end
    else
      _ -> {:noreply, forbidden(socket)}
    end
  end

  def handle_async({:network, id}, {:ok, result}, socket) do
    socket = socket |> assign(:busy, MapSet.delete(socket.assigns.busy, id)) |> load()

    case result do
      {:ok, _} ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, :error, NetworkConnections.error_message(reason))}
    end
  end

  def handle_async({:network, id}, {:exit, _}, socket) do
    {:noreply,
     socket
     |> assign(:busy, MapSet.delete(socket.assigns.busy, id))
     |> assign(:error, "Connection operation failed. Refresh and try again.")}
  end

  defp run(socket, connection, action) do
    socket
    |> assign(:error, nil)
    |> assign(:busy, MapSet.put(socket.assigns.busy, connection.id))
    |> start_async({:network, connection.id}, fn ->
      apply(NetworkConnections, action, [connection])
    end)
  end

  defp load(socket),
    do:
      assign(
        socket,
        :connections,
        NetworkConnections.list(socket.assigns.current_membership.organization_id)
      )

  defp forbidden(socket),
    do:
      assign(
        socket,
        :error,
        "Only organization owners and admins can manage network connections."
      )

  defp changeset_error(changeset) do
    Enum.map_join(changeset.errors, "; ", fn {field, {message, _}} -> "#{field}: #{message}" end)
  end

  defp status_label("online"), do: "Connected"
  defp status_label("pending"), do: "Enrollment pending"
  defp status_label("approval_required"), do: "Waiting for device approval"
  defp status_label("needs_authorization"), do: "Authorization required"
  defp status_label("disconnected"), do: "Disconnected"
  defp status_label(_), do: "Connection error"
end
