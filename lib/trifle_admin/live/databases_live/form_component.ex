defmodule TrifleAdmin.DatabasesLive.FormComponent do
  use TrifleAdmin, :live_component

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form_container for={@form} phx-target={@myself} phx-change="validate" phx-submit="save">
        <:header title={@title} subtitle="Configure database connection for Trifle::Stats drivers" />
        
        <.form_field field={@form[:display_name]} label="Display Name" required />
        
        <.form_field 
          field={@form[:driver]} 
          type="select" 
          label="Driver" 
          options={Database.drivers() |> Enum.map(&{String.capitalize(&1), &1})} 
          prompt="Choose a driver..." 
          disabled={@action == :edit}
        />
        
        <%= if @selected_driver && Database.requires_host?(@selected_driver) do %>
          <.form_field field={@form[:host]} label="Host" />
        <% end %>
        
        <%= if @selected_driver && Database.requires_port?(@selected_driver) do %>
          <.form_field 
            field={@form[:port]} 
            type="number" 
            label="Port" 
            placeholder={if @selected_driver, do: to_string(Database.default_port(@selected_driver)), else: ""}
          />
        <% end %>
        
        <%= if @selected_driver && @selected_driver != "redis" && @selected_driver != "sqlite" do %>
          <.form_field field={@form[:database_name]} label="Database Name" />
        <% end %>
        
        <%= if @selected_driver && @selected_driver == "sqlite" do %>
          <.form_field 
            field={@form[:file_path]} 
            label="Database File Path" 
            placeholder="e.g., /path/to/database.sqlite"
          />
        <% end %>
        
        <%= if @selected_driver && Database.shows_username?(@selected_driver) do %>
          <.form_field field={@form[:username]} label="Username" />
        <% end %>
        
        <%= if @selected_driver && Database.shows_password?(@selected_driver) do %>
          <.form_field field={@form[:password]} type="password" label="Password" />
        <% end %>
        
        <%= if @selected_driver == "mongo" do %>
          <.form_field 
            field={@form[:auth_database]} 
            label="Authentication Database" 
            help_text="Database to authenticate against (usually 'admin'). Leave empty to authenticate against the target database."
            placeholder="admin"
          />
        <% end %>
        
        <%= if @selected_driver do %>
          <div class="border-t pt-6 mt-6">
            <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Time Configuration</h3>
          
          <div class="space-y-2">
            <label for={@form[:granularities].id} class="block text-sm font-medium text-gray-900 dark:text-white">
              Granularities
            </label>
            <input 
              id={@form[:granularities].id}
              name={@form[:granularities].name}
              type="text" 
              value={granularities_to_string(@form[:granularities].value)}
              placeholder="1m, 1h, 1d, 1w, 1mo, 1q, 1y"
              class="block w-full rounded-lg border border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" 
            />
            <p class="text-xs text-gray-600 dark:text-gray-400">Default: 1m, 1h, 1d, 1w, 1mo, 1q, 1y</p>
            <%= for error <- @form[:granularities].errors do %>
              <p class="text-sm text-red-600 dark:text-red-400"><%= translate_error(error) %></p>
            <% end %>
          </div>
          
          <.form_field 
            field={@form[:time_zone]} 
            type="select" 
            label="Time Zone" 
            options={@time_zones}
          />
        </div>
        <% end %>
        
        <%= if @selected_driver && map_size(@config_options) > 0 do %>
          <div class="border-t pt-6 mt-6">
            <h3 class="text-sm font-semibold text-gray-900 dark:text-white mb-4">Configuration Options</h3>
            <p class="text-xs text-gray-600 dark:text-gray-400 mb-4">Driver-specific configuration settings.</p>
            
            <%= for {key, value} <- sort_config_options(@config_options) do %>
              <%= case config_field_type(key, @selected_driver) do %>
                <% :boolean -> %>
                  <div class="mb-4">
                    <input 
                      name={"database[config][#{key}]"} 
                      type="hidden" 
                      value="false"
                    />
                    <label class="flex items-center space-x-3">
                      <input 
                        name={"database[config][#{key}]"} 
                        type="checkbox" 
                        checked={is_config_value_true(@form, key, value)}
                        value="true"
                        class="rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:border-gray-600 dark:bg-gray-700" 
                      />
                      <span class="text-sm font-medium text-gray-900 dark:text-white"><%= humanize_config_key(key) %></span>
                    </label>
                  </div>
                <% :integer -> %>
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2">
                      <%= humanize_config_key(key) %><%= if is_nullable_field?(key), do: " (Optional)" %>
                    </label>
                    <input 
                      name={"database[config][#{key}]"} 
                      type="number" 
                      value={format_integer_value(get_config_value(@form, key, value))}
                      placeholder={if is_nullable_field?(key), do: "Leave empty for no expiration", else: nil}
                      class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" 
                    />
                  </div>
                <% :string -> %>
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-900 dark:text-white mb-2"><%= humanize_config_key(key) %></label>
                    <input 
                      name={"database[config][#{key}]"} 
                      type="text" 
                      value={get_config_value(@form, key, value)}
                      class="block w-full rounded-md border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm" 
                    />
                  </div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      
        <:actions>
          <.form_actions>
            <.primary_button phx-disable-with="Saving...">Save Database</.primary_button>
            <.secondary_button phx-click={JS.patch(~p"/admin/databases")}>Cancel</.secondary_button>
          </.form_actions>
        </:actions>
      </.form_container>
    </div>
    """
  end

  @impl true
  def update(%{database: database} = assigns, socket) do
    changeset = Organizations.change_database(database)
    selected_driver = database.driver
    config_options = if selected_driver, do: Database.default_config_options(selected_driver), else: %{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_driver, selected_driver)
     |> assign(:config_options, config_options)
     |> assign(:time_zones, time_zones())
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"database" => database_params}, socket) do
    selected_driver = case database_params["driver"] do
      nil -> socket.assigns.database.driver  # Fall back to existing driver
      "" -> nil
      driver -> driver
    end
    
    config_options = if selected_driver, do: Database.default_config_options(selected_driver), else: %{}

    changeset =
      socket.assigns.database
      |> Organizations.change_database(database_params)
      |> Map.put(:action, :validate)

    {:noreply, 
     socket 
     |> assign(:selected_driver, selected_driver)
     |> assign(:config_options, config_options)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"database" => database_params}, socket) do
    save_database(socket, socket.assigns.action, database_params)
  end

  defp save_database(socket, :edit, database_params) do
    case Organizations.update_database(socket.assigns.database, database_params) do
      {:ok, database} ->
        notify_parent({:saved, database})

        {:noreply,
         socket
         |> put_flash(:info, "Database updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_database(socket, :new, database_params) do
    case Organizations.create_database(database_params) do
      {:ok, database} ->
        notify_parent({:saved, database})

        {:noreply,
         socket
         |> put_flash(:info, "Database created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

  defp config_field_type("ssl", "postgres"), do: :boolean
  defp config_field_type("joined_identifiers", _), do: :boolean
  defp config_field_type("pool_size", _), do: :integer
  defp config_field_type("pool_timeout", _), do: :integer
  defp config_field_type("timeout", _), do: :integer
  defp config_field_type("expire_after", _), do: :integer
  defp config_field_type(_, _), do: :string

  defp humanize_config_key(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
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

  defp is_config_value_true(form, key, default_value) do
    value = get_config_value(form, key, default_value)
    case value do
      true -> true
      "true" -> true
      _ -> false
    end
  end

  defp is_nullable_field?("expire_after"), do: true
  defp is_nullable_field?(_), do: false

  defp format_integer_value(nil), do: ""
  defp format_integer_value(value) when is_integer(value), do: to_string(value)
  defp format_integer_value(value) when is_binary(value), do: value
  defp format_integer_value(_), do: ""

  # Convert granularities list to comma-separated string for form display
  defp granularities_to_string(nil), do: ""
  defp granularities_to_string([]), do: ""
  defp granularities_to_string(granularities) when is_list(granularities) do
    Enum.join(granularities, ", ")
  end
  defp granularities_to_string(value) when is_binary(value), do: value
  defp granularities_to_string(_), do: ""

  # Sort configuration options to put table/collection names first
  defp sort_config_options(config_options) when is_map(config_options) do
    config_options
    |> Enum.sort_by(fn {key, _value} ->
      case key do
        "table_name" -> 0
        "collection_name" -> 1
        _ -> 2
      end
    end)
  end

  defp time_zones do
    now = DateTime.utc_now()

    Tzdata.zone_list()
    |> Enum.map(fn zone ->
      tzinfo = Timex.Timezone.get(zone, now)
      offset = Timex.TimezoneInfo.format_offset(tzinfo)
      label = "#{tzinfo.full_name} - #{tzinfo.abbreviation} (#{offset})"

      {label, tzinfo.full_name}
    end)
    |> Enum.uniq()
  end
end