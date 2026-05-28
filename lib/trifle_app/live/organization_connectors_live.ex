defmodule TrifleApp.OrganizationConnectorsLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationConnector
  alias Trifle.Organizations.OrganizationMembership
  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Private Connectors")
      |> assign(:active_tab, :connectors)
      |> assign(:show_create_modal, false)
      |> assign(:issued_connector, nil)
      |> assign(:issued_token, nil)
      |> assign(:connector_error, nil)
      |> assign(:new_connector_name, "")
      |> assign(:connector_install_tab, "docker")

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization/profile")}

      true ->
        {:ok, load_state(socket, membership)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <%= if @current_membership do %>
        <Navigation.nav active_tab={@active_tab} />

        <div class="sm:flex sm:items-center">
          <div class="sm:flex-auto">
            <h1 class="text-base font-semibold leading-6 text-gray-900 dark:text-white">
              Private Connectors
            </h1>
            <p class="mt-2 text-sm text-gray-500 dark:text-slate-400">
              Connect private databases through a Private Connector running inside your network.
            </p>
          </div>
          <%= if @can_manage do %>
            <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
              <.primary_button type="button" phx-click="open_create_modal" class="gap-2">
                <span>New connector</span>
              </.primary_button>
            </div>
          <% end %>
        </div>

        <div class="mt-6 overflow-hidden rounded-lg bg-white shadow-sm dark:bg-slate-800">
          <div class="border-b border-gray-100 px-4 py-3 text-sm font-semibold text-gray-900 dark:border-slate-700 dark:text-white">
            Private Connectors ({length(@connectors)})
          </div>

          <%= if Enum.empty?(@connectors) do %>
            <div class="px-6 py-12 text-center text-sm text-gray-500 dark:text-slate-400">
              No private connectors yet.
            </div>
          <% else %>
            <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-700">
              <%= for connector <- @connectors do %>
                <li class="px-4 py-4 sm:px-6">
                  <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div class="min-w-0">
                      <div class="flex flex-wrap items-center gap-2">
                        <p class="text-sm font-medium text-gray-900 dark:text-white">
                          {connector.name}
                        </p>
                        <span class={status_badge_classes(connector_status(connector))}>
                          {status_label(connector_status(connector))}
                        </span>
                      </div>
                      <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                        Token ends in {connector.token_last5 || "unknown"} · Last seen: {format_datetime(
                          connector.last_seen_at
                        )}
                      </p>
                      <div class="mt-2 flex flex-wrap items-center gap-1.5 text-xs text-gray-500 dark:text-slate-400">
                        <%= if Enum.empty?(connector.capabilities || []) do %>
                          <span>No capabilities reported yet</span>
                        <% else %>
                          <%= for capability <- connector.capabilities do %>
                            <span class="rounded-full border border-gray-200 px-2 py-0.5 text-gray-700 dark:border-slate-700 dark:text-slate-200">
                              {capability}
                            </span>
                          <% end %>
                        <% end %>
                      </div>
                      <p
                        :if={connector.hostname}
                        class="mt-1 text-xs text-gray-500 dark:text-slate-400"
                      >
                        Host: {connector.hostname} · Version: {connector.version || "unknown"}
                      </p>
                    </div>

                    <%= if @can_manage do %>
                      <button
                        type="button"
                        phx-click="delete_connector"
                        phx-value-id={connector.id}
                        data-confirm="Delete this private connector? Databases using it will switch back to direct connections."
                        class="inline-flex items-center justify-center rounded-md border border-red-200 bg-white px-3 py-2 text-xs font-medium text-red-600 hover:bg-red-50 dark:border-red-400 dark:bg-slate-800 dark:text-red-300 dark:hover:bg-red-500/10"
                      >
                        Delete
                      </button>
                    <% end %>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </div>

        <.app_modal
          id="organization-connector-modal"
          show={@show_create_modal}
          on_cancel={JS.push("close_create_modal")}
          size="lg"
        >
          <:title>
            <%= if @issued_token do %>
              Private connector created
            <% else %>
              Create connector
            <% end %>
          </:title>
          <:body>
            <%= if @issued_token do %>
              <div class="space-y-4">
                <p class="text-sm text-gray-600 dark:text-slate-300">
                  Copy the token now. You will not be able to see it again.
                </p>
                <code
                  id="organization_connector_token"
                  class="block max-w-full break-all rounded-md bg-red-100 px-3 py-2 font-mono text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200"
                >
                  {@issued_token}
                </code>
                <div>
                  <div class="flex items-center justify-between gap-3">
                    <div class="inline-flex rounded-md border border-gray-200 bg-gray-50 p-1 text-xs font-medium dark:border-slate-700 dark:bg-slate-900">
                      <button
                        type="button"
                        phx-click="select_connector_install_tab"
                        phx-value-tab="docker"
                        class={connector_install_tab_classes(@connector_install_tab == "docker")}
                      >
                        Docker
                      </button>
                      <button
                        type="button"
                        phx-click="select_connector_install_tab"
                        phx-value-tab="kubernetes"
                        class={connector_install_tab_classes(@connector_install_tab == "kubernetes")}
                      >
                        Kubernetes
                      </button>
                    </div>
                  </div>
                  <%= if @connector_install_tab == "kubernetes" do %>
                    <pre
                      id="organization_connector_kubernetes_manifest"
                      class="mt-2 max-h-72 overflow-x-auto rounded-md px-3 py-2 font-mono text-xs leading-5 shadow-inner"
                      style="background-color: #0f172a; color: #f8fafc;"
                    ><code>{kubernetes_install_command(@issued_connector, @issued_token)}</code></pre>
                  <% else %>
                    <pre
                      id="organization_connector_docker_command"
                      class="mt-2 max-h-56 overflow-x-auto rounded-md px-3 py-2 font-mono text-xs leading-5 shadow-inner"
                      style="background-color: #0f172a; color: #f8fafc;"
                    ><code>{docker_command(@issued_connector, @issued_token)}</code></pre>
                  <% end %>
                  <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
                    Replace <code>db.internal:5432</code>
                    with the database host and port this connector may reach.
                  </p>
                </div>
                <div class="flex justify-end gap-2">
                  <button
                    type="button"
                    phx-click={
                      JS.dispatch("phx:copy", to: connector_install_target(@connector_install_tab))
                    }
                    class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200"
                  >
                    Copy {connector_install_label(@connector_install_tab)}
                  </button>
                  <button
                    type="button"
                    phx-click="close_create_modal"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white hover:bg-teal-500"
                  >
                    Done
                  </button>
                </div>
              </div>
            <% else %>
              <form phx-submit="create_connector" phx-change="change_connector_form" class="space-y-4">
                <%= if @connector_error do %>
                  <div class="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-500/10 dark:text-red-200">
                    {@connector_error}
                  </div>
                <% end %>

                <label class="block text-sm">
                  <span class="text-gray-700 dark:text-slate-200">Name</span>
                  <input
                    type="text"
                    name="connector[name]"
                    value={@new_connector_name}
                    placeholder="Production VPC"
                    class="mt-1 block w-full rounded-md border border-gray-300 bg-white px-2.5 py-2 text-sm text-gray-900 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
                  />
                </label>

                <div class="flex justify-end gap-2">
                  <button
                    type="button"
                    phx-click="close_create_modal"
                    class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white hover:bg-teal-500"
                  >
                    Create connector
                  </button>
                </div>
              </form>
            <% end %>
          </:body>
        </.app_modal>
      <% end %>
    </div>
    """
  end

  def handle_event("open_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, true)
     |> assign(:issued_connector, nil)
     |> assign(:issued_token, nil)
     |> assign(:connector_error, nil)
     |> assign(:new_connector_name, "")
     |> assign(:connector_install_tab, "docker")}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_create_modal, false)
     |> assign(:issued_connector, nil)
     |> assign(:issued_token, nil)
     |> assign(:connector_error, nil)
     |> assign(:new_connector_name, "")
     |> assign(:connector_install_tab, "docker")}
  end

  def handle_event("select_connector_install_tab", %{"tab" => tab}, socket)
      when tab in ["docker", "kubernetes"] do
    {:noreply, assign(socket, :connector_install_tab, tab)}
  end

  def handle_event("change_connector_form", %{"connector" => params}, socket) do
    {:noreply, assign(socket, :new_connector_name, params["name"] || "")}
  end

  def handle_event("create_connector", %{"connector" => params}, socket) do
    membership = socket.assigns.current_membership

    if socket.assigns.can_manage do
      organization = Organizations.get_organization!(membership.organization_id)

      case Organizations.create_connector_for_org(organization, params) do
        {:ok, connector, token} ->
          {:noreply,
           socket
           |> load_state(membership)
           |> assign(:show_create_modal, true)
           |> assign(:issued_connector, connector)
           |> assign(:issued_token, token)
           |> assign(:connector_error, nil)
           |> assign(:connector_install_tab, "docker")}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:connector_error, first_error(changeset))
           |> assign(:new_connector_name, params["name"] || "")}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Only organization owners and admins can manage private connectors."
       )}
    end
  end

  def handle_event("delete_connector", %{"id" => id}, socket) do
    membership = socket.assigns.current_membership

    with true <- socket.assigns.can_manage,
         %OrganizationConnector{} = connector <-
           Organizations.get_connector_for_org(membership.organization_id, id),
         {:ok, _deleted} <- Organizations.delete_connector(connector) do
      {:noreply,
       socket
       |> load_state(membership)
       |> put_flash(:info, "Private connector deleted successfully.")}
    else
      false ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Only organization owners and admins can manage private connectors."
         )}

      nil ->
        {:noreply, put_flash(socket, :error, "Private connector could not be found.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Private connector could not be deleted.")}
    end
  end

  defp load_state(socket, %OrganizationMembership{} = membership) do
    can_manage =
      Organizations.membership_owner?(membership) or Organizations.membership_admin?(membership)

    socket
    |> assign(:current_membership, membership)
    |> assign(:can_manage, can_manage)
    |> assign(:connectors, Organizations.list_connectors_for_org(membership.organization_id))
  end

  defp connector_status(%OrganizationConnector{status: "online", last_seen_at: last_seen_at}) do
    if stale?(last_seen_at), do: "offline", else: "online"
  end

  defp connector_status(%OrganizationConnector{status: status}), do: status || "pending"

  defp stale?(nil), do: true

  defp stale?(%DateTime{} = value) do
    DateTime.diff(DateTime.utc_now(), value, :second) > 90
  end

  defp status_label("online"), do: "Online"
  defp status_label("offline"), do: "Offline"
  defp status_label("error"), do: "Error"
  defp status_label(_), do: "Pending"

  defp status_badge_classes("online") do
    "inline-flex rounded-full bg-emerald-50 px-2 py-0.5 text-xs font-medium text-emerald-700 ring-1 ring-emerald-600/20 dark:bg-emerald-500/10 dark:text-emerald-200"
  end

  defp status_badge_classes("offline") do
    "inline-flex rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-700 ring-1 ring-slate-500/20 dark:bg-slate-700 dark:text-slate-200"
  end

  defp status_badge_classes("error") do
    "inline-flex rounded-full bg-red-50 px-2 py-0.5 text-xs font-medium text-red-700 ring-1 ring-red-600/20 dark:bg-red-500/10 dark:text-red-200"
  end

  defp status_badge_classes(_) do
    "inline-flex rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-700 ring-1 ring-amber-600/20 dark:bg-amber-500/10 dark:text-amber-200"
  end

  defp format_datetime(nil), do: "never"

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")
  end

  defp docker_command(%OrganizationConnector{} = connector, token) do
    cloud_url = TrifleWeb.Endpoint.url()

    Enum.join(
      [
        "docker run -d --name trifle-connector",
        docker_env("TRIFLE_CLOUD_URL", cloud_url),
        docker_env("TRIFLE_CONNECTOR_ID", connector.id),
        docker_env("TRIFLE_CONNECTOR_TOKEN", token),
        docker_env("TRIFLE_CONNECTOR_NAME", connector.name),
        docker_env("TRIFLE_CONNECTOR_ALLOWED_HOSTS", "db.internal:5432"),
        "trifle/connector:latest"
      ],
      " \\\n  "
    )
  end

  defp docker_command(_, _), do: ""

  defp kubernetes_install_command(%OrganizationConnector{} = connector, token) do
    manifest = kubernetes_manifest(connector, token)

    [
      "cat > trifle-connector.yaml <<'YAML'",
      manifest,
      "YAML",
      "",
      "kubectl apply -f trifle-connector.yaml"
    ]
    |> Enum.join("\n")
  end

  defp kubernetes_install_command(_, _), do: ""

  defp kubernetes_manifest(%OrganizationConnector{} = connector, token) do
    cloud_url = TrifleWeb.Endpoint.url()

    [
      "apiVersion: v1",
      "kind: Secret",
      "metadata:",
      "  name: trifle-connector",
      "type: Opaque",
      "stringData:",
      "  TRIFLE_CONNECTOR_TOKEN: #{yaml_quote(token)}",
      "---",
      "apiVersion: apps/v1",
      "kind: Deployment",
      "metadata:",
      "  name: trifle-connector",
      "  labels:",
      "    app.kubernetes.io/name: trifle-connector",
      "spec:",
      "  replicas: 1",
      "  selector:",
      "    matchLabels:",
      "      app.kubernetes.io/name: trifle-connector",
      "  template:",
      "    metadata:",
      "      labels:",
      "        app.kubernetes.io/name: trifle-connector",
      "    spec:",
      "      containers:",
      "        - name: connector",
      "          image: trifle/connector:latest",
      "          imagePullPolicy: Always",
      "          env:",
      "            - name: TRIFLE_CLOUD_URL",
      "              value: #{yaml_quote(cloud_url)}",
      "            - name: TRIFLE_CONNECTOR_ID",
      "              value: #{yaml_quote(connector.id)}",
      "            - name: TRIFLE_CONNECTOR_NAME",
      "              value: #{yaml_quote(connector.name)}",
      "            - name: TRIFLE_CONNECTOR_ALLOWED_HOSTS",
      "              value: 'db.internal:5432'",
      "            - name: TRIFLE_CONNECTOR_HEALTH_ADDR",
      "              value: '0.0.0.0:8080'",
      "            - name: TRIFLE_CONNECTOR_TOKEN",
      "              valueFrom:",
      "                secretKeyRef:",
      "                  name: trifle-connector",
      "                  key: TRIFLE_CONNECTOR_TOKEN",
      "          ports:",
      "            - name: http",
      "              containerPort: 8080",
      "          readinessProbe:",
      "            httpGet:",
      "              path: /readyz",
      "              port: http",
      "            initialDelaySeconds: 5",
      "            periodSeconds: 10",
      "          livenessProbe:",
      "            httpGet:",
      "              path: /healthz",
      "              port: http",
      "            initialDelaySeconds: 10",
      "            periodSeconds: 30"
    ]
    |> Enum.join("\n")
  end

  defp connector_install_tab_classes(true) do
    "rounded px-3 py-1.5 text-gray-900 shadow-sm bg-white dark:bg-slate-700 dark:text-white"
  end

  defp connector_install_tab_classes(false) do
    "rounded px-3 py-1.5 text-gray-500 hover:text-gray-900 dark:text-slate-400 dark:hover:text-slate-100"
  end

  defp connector_install_target("kubernetes"), do: "#organization_connector_kubernetes_manifest"
  defp connector_install_target(_tab), do: "#organization_connector_docker_command"

  defp connector_install_label("kubernetes"), do: "manifest"
  defp connector_install_label(_tab), do: "command"

  defp docker_env(key, value), do: "-e #{key}=#{shell_quote(value)}"

  defp shell_quote(value) do
    value = value |> to_string() |> String.replace("'", "'\"'\"'")
    "'#{value}'"
  end

  defp yaml_quote(value) do
    value = value |> to_string() |> String.replace("'", "''")
    "'#{value}'"
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, errors} ->
      Enum.map(errors, fn error -> "#{Phoenix.Naming.humanize(field)} #{error}" end)
    end)
    |> List.first()
    |> case do
      nil -> "Private connector could not be created."
      message -> message
    end
  end
end
