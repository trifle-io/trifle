defmodule TrifleAdmin.ProjectClustersLive.FormComponent do
  use TrifleAdmin, :live_component

  alias Phoenix.LiveView.JS
  alias Trifle.Organizations
  alias Trifle.Organizations.ProjectCluster

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form_container for={@form} phx-target={@myself} phx-change="validate" phx-submit="save">
        <:header title={@title} subtitle="Configure storage clusters for projects." />

        <.form_field field={@form[:name]} label="Name" required />
        <.form_field field={@form[:code]} label="Code" required />

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:driver]}
            type="select"
            label="Driver"
            options={driver_options()}
            prompt="Choose a driver..."
            disabled={@action == :edit}
          />
          <.form_field field={@form[:status]} type="select" label="Status" options={status_options()} />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:visibility]}
            type="select"
            label="Visibility"
            options={visibility_options()}
          />
          <.form_field field={@form[:is_default]} type="checkbox" label="Default cluster" />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <.form_field field={@form[:region]} label="Region" />
          <.form_field field={@form[:city]} label="City" />
          <.form_field field={@form[:country]} label="Country" />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field field={@form[:host]} label="Host" />
          <.form_field field={@form[:port]} type="number" label="Port" />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field field={@form[:database_name]} label="Database Name" />
          <.form_field
            field={@form[:auth_database]}
            label="Auth Database"
            help_text="Database to authenticate against (usually 'admin')."
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field field={@form[:username]} label="Username" />
          <.form_field field={@form[:password]} type="password" label="Password" />
        </div>

        <div class="border-t pt-6 mt-6">
          <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">
            Driver Options
          </h3>
          <p class="text-xs text-gray-600 dark:text-gray-400 mb-4">
            Applied to the project cluster connection pool.
          </p>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                Collection Name
              </label>
              <input
                name="project_cluster[config][collection_name]"
                type="text"
                value={
                  get_config_value(@form, "collection_name", @config_defaults["collection_name"])
                }
                class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                Joined Identifiers
              </label>
              <% selected =
                joined_identifiers_value(
                  @form,
                  "joined_identifiers",
                  @config_defaults["joined_identifiers"]
                ) %>
              <select
                name="project_cluster[config][joined_identifiers]"
                class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              >
                <%= for {label, option_value} <- joined_identifiers_options() do %>
                  <option value={option_value} selected={selected == option_value}>
                    {label}
                  </option>
                <% end %>
              </select>
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mt-4">
            <div>
              <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                Pool Size
              </label>
              <input
                name="project_cluster[config][pool_size]"
                type="number"
                value={
                  format_integer_value(
                    get_config_value(@form, "pool_size", @config_defaults["pool_size"])
                  )
                }
                class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                Pool Timeout (ms)
              </label>
              <input
                name="project_cluster[config][pool_timeout]"
                type="number"
                value={
                  format_integer_value(
                    get_config_value(@form, "pool_timeout", @config_defaults["pool_timeout"])
                  )
                }
                class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
            </div>
            <div>
              <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                Timeout (ms)
              </label>
              <input
                name="project_cluster[config][timeout]"
                type="number"
                value={
                  format_integer_value(
                    get_config_value(@form, "timeout", @config_defaults["timeout"])
                  )
                }
                class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
            </div>
          </div>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mt-4">
            <div>
              <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                Expire After (seconds)
              </label>
              <input
                name="project_cluster[config][expire_after]"
                type="number"
                value={
                  format_integer_value(
                    get_config_value(@form, "expire_after", @config_defaults["expire_after"])
                  )
                }
                placeholder="Leave empty for no expiration"
                class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm"
              />
            </div>
          </div>
        </div>

        <:actions>
          <.form_actions>
            <.secondary_button type="button" phx-click={JS.patch(@patch)}>
              Cancel
            </.secondary_button>
            <.primary_button phx-disable-with="Saving...">Save Cluster</.primary_button>
          </.form_actions>
        </:actions>
      </.form_container>
    </div>
    """
  end

  @impl true
  def update(%{project_cluster: project_cluster} = assigns, socket) do
    changeset = Organizations.change_project_cluster(project_cluster)
    selected_driver = project_cluster.driver || "mongo"
    config_defaults = ProjectCluster.default_config_options(selected_driver)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, assigns[:title] || "Project Cluster")
     |> assign(:selected_driver, selected_driver)
     |> assign(:config_defaults, config_defaults)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"project_cluster" => params}, socket) do
    selected_driver =
      case params["driver"] do
        nil -> socket.assigns.selected_driver
        "" -> nil
        driver -> driver
      end

    config_defaults =
      if selected_driver, do: ProjectCluster.default_config_options(selected_driver), else: %{}

    changeset =
      socket.assigns.project_cluster
      |> Organizations.change_project_cluster(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:selected_driver, selected_driver)
     |> assign(:config_defaults, config_defaults)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"project_cluster" => params}, socket) do
    save_cluster(socket, params)
  end

  defp save_cluster(%{assigns: %{action: :new}} = socket, params) do
    case Organizations.create_project_cluster(params) do
      {:ok, cluster} ->
        notify_parent({:saved, cluster})

        {:noreply,
         socket
         |> put_flash(:info, "Project cluster created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_cluster(%{assigns: %{action: :edit}} = socket, params) do
    case Organizations.update_project_cluster(socket.assigns.project_cluster, params) do
      {:ok, cluster} ->
        notify_parent({:saved, cluster})

        {:noreply,
         socket
         |> put_flash(:info, "Project cluster updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp driver_options do
    ProjectCluster.drivers()
    |> Enum.map(&{String.capitalize(&1), &1})
  end

  defp status_options do
    ProjectCluster.statuses()
    |> Enum.map(fn status ->
      {status |> String.replace("_", " ") |> String.capitalize(), status}
    end)
  end

  defp visibility_options do
    ProjectCluster.visibilities()
    |> Enum.map(fn visibility ->
      {String.capitalize(visibility), visibility}
    end)
  end

  defp get_config_value(form, key, default_value) do
    case form.params do
      %{"config" => config} when is_map(config) ->
        Map.get(config, key, default_value)

      _ ->
        case form.data.config do
          nil -> default_value
          config when is_map(config) -> Map.get(config, key, default_value)
          _ -> default_value
        end
    end
  end

  defp joined_identifiers_options do
    [
      {"Separated (null)", "null"},
      {"Partial (partial)", "partial"},
      {"Joined (full)", "full"}
    ]
  end

  defp joined_identifiers_value(form, key, default_value) do
    value = get_config_value(form, key, default_value)

    case value do
      nil -> "null"
      "" -> "null"
      "null" -> "null"
      false -> "null"
      "false" -> "null"
      true -> "full"
      "true" -> "full"
      :full -> "full"
      "full" -> "full"
      :partial -> "partial"
      "partial" -> "partial"
      _ -> "full"
    end
  end

  defp format_integer_value(nil), do: ""
  defp format_integer_value(value) when is_integer(value), do: to_string(value)
  defp format_integer_value(value) when is_binary(value), do: value
  defp format_integer_value(_), do: ""
end
