defmodule TrifleAdmin.DatabasesLive.FormComponent do
  use TrifleAdmin, :live_component

  alias Trifle.Organizations
  alias Trifle.Organizations.Database

  @impl true
  def render(assigns) do
    ~H"""
    <div class="overflow-hidden bg-white shadow-sm sm:rounded-lg">
      <div class="px-4 py-6 sm:px-6">
        <h3 class="text-base/7 font-semibold text-gray-900"><%= @title %></h3>
        <p class="mt-1 max-w-2xl text-sm/6 text-gray-500">Configure database connection for Trifle::Stats drivers</p>
      </div>
      
      <form phx-target={@myself} phx-change="validate" phx-submit="save">
        <div class="space-y-12 sm:space-y-16">
          <div>
            <div class="border-t border-gray-100 mt-10 space-y-8 border-b border-gray-900/10 pb-12 sm:space-y-0 sm:divide-y sm:divide-gray-900/10 sm:border-t-gray-900/10 sm:pb-0">
              
              <!-- Display Name -->
              <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                <label for="database_display_name" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Display Name</label>
                <div class="mt-2 sm:col-span-2 sm:mt-0">
                  <input 
                    id="database_display_name" 
                    name="database[display_name]" 
                    type="text" 
                    value={@form[:display_name].value}
                    class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-md sm:text-sm/6" 
                  />
                  <%= for error <- @form[:display_name].errors do %>
                    <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                  <% end %>
                </div>
              </div>
              
              <!-- Driver -->
              <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                <label for="database_driver" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Driver</label>
                <div class="mt-2 sm:col-span-2 sm:mt-0">
                  <div class="grid grid-cols-1 sm:max-w-xs">
                    <select 
                      id="database_driver" 
                      name="database[driver]" 
                      class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pr-8 pl-3 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:text-sm/6"
                      disabled={@action == :edit}
                    >
                      <option value="">Choose a driver...</option>
                      <%= for driver <- Database.drivers() do %>
                        <option value={driver} selected={@form[:driver].value == driver}>
                          <%= String.capitalize(driver) %>
                        </option>
                      <% end %>
                    </select>
                    <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 sm:size-4">
                      <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
                    </svg>
                  </div>
                  <%= for error <- @form[:driver].errors do %>
                    <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                  <% end %>
                </div>
              </div>
              
              <!-- Host -->
              <%= if @selected_driver && Database.requires_host?(@selected_driver) do %>
                <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                  <label for="database_host" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Host</label>
                  <div class="mt-2 sm:col-span-2 sm:mt-0">
                    <input 
                      id="database_host" 
                      name="database[host]" 
                      type="text" 
                      value={@form[:host].value}
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-md sm:text-sm/6" 
                    />
                    <%= for error <- @form[:host].errors do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
              <!-- Port -->
              <%= if @selected_driver && Database.requires_port?(@selected_driver) do %>
                <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                  <label for="database_port" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Port</label>
                  <div class="mt-2 sm:col-span-2 sm:mt-0">
                    <input 
                      id="database_port" 
                      name="database[port]" 
                      type="number" 
                      value={@form[:port].value}
                      placeholder={if @selected_driver, do: to_string(Database.default_port(@selected_driver)), else: ""}
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-xs sm:text-sm/6" 
                    />
                    <%= for error <- @form[:port].errors do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
              <!-- Database Name -->
              <%= if @selected_driver && @selected_driver != "redis" && @selected_driver != "sqlite" do %>
                <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                  <label for="database_database_name" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Database Name</label>
                  <div class="mt-2 sm:col-span-2 sm:mt-0">
                    <input 
                      id="database_database_name" 
                      name="database[database_name]" 
                      type="text" 
                      value={@form[:database_name].value}
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-md sm:text-sm/6" 
                    />
                    <%= for error <- @form[:database_name].errors do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
              <!-- File Path for SQLite -->
              <%= if @selected_driver && @selected_driver == "sqlite" do %>
                <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                  <label for="database_file_path" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Database File Path</label>
                  <div class="mt-2 sm:col-span-2 sm:mt-0">
                    <input 
                      id="database_file_path" 
                      name="database[file_path]" 
                      type="text" 
                      value={@form[:file_path].value}
                      placeholder="e.g., /path/to/database.sqlite"
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-xl sm:text-sm/6" 
                    />
                    <%= for error <- @form[:file_path].errors do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
              <!-- Username -->
              <%= if @selected_driver && Database.shows_username?(@selected_driver) do %>
                <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                  <label for="database_username" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Username</label>
                  <div class="mt-2 sm:col-span-2 sm:mt-0">
                    <input 
                      id="database_username" 
                      name="database[username]" 
                      type="text" 
                      value={@form[:username].value}
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-md sm:text-sm/6" 
                    />
                    <%= for error <- @form[:username].errors do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                    <% end %>
                  </div>
                </div>
              <% end %>
              
              <!-- Password -->
              <%= if @selected_driver && Database.shows_password?(@selected_driver) do %>
                <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                  <label for="database_password" class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5">Password</label>
                  <div class="mt-2 sm:col-span-2 sm:mt-0">
                    <input 
                      id="database_password" 
                      name="database[password]" 
                      type="password" 
                      value={@form[:password].value}
                      class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-md sm:text-sm/6" 
                    />
                    <%= for error <- @form[:password].errors do %>
                      <p class="mt-2 text-sm text-red-600"><%= translate_error(error) %></p>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          
          <!-- Configuration Options -->
          <%= if @selected_driver && map_size(@config_options) > 0 do %>
            <div>
              <h2 class="text-base/7 font-semibold text-gray-900">Configuration Options</h2>
              <p class="mt-1 max-w-2xl text-sm/6 text-gray-600">Driver-specific configuration settings.</p>
              
              <div class="mt-10 space-y-8 border-b border-gray-900/10 pb-12 sm:space-y-0 sm:divide-y sm:divide-gray-900/10 sm:border-t sm:border-t-gray-900/10 sm:pb-0">
                <%= for {key, value} <- @config_options do %>
                  <%= case config_field_type(key, @selected_driver) do %>
                    <% :boolean -> %>
                      <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                        <label class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5"><%= humanize_config_key(key) %></label>
                        <div class="mt-2 sm:col-span-2 sm:mt-0">
                          <div class="flex gap-3">
                            <div class="flex h-6 shrink-0 items-center">
                              <div class="group grid size-4 grid-cols-1">
                                <input 
                                  name={"database[config][#{key}]"} 
                                  type="checkbox" 
                                  checked={get_config_value(@form, key, value) == true}
                                  value="true"
                                  class="col-start-1 row-start-1 appearance-none rounded-sm border border-gray-300 bg-white checked:border-indigo-600 checked:bg-indigo-600 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600" 
                                />
                                <svg viewBox="0 0 14 14" fill="none" class="pointer-events-none col-start-1 row-start-1 size-3.5 self-center justify-self-center stroke-white">
                                  <path d="M3 8L6 11L11 3.5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="opacity-0 group-has-checked:opacity-100" />
                                </svg>
                              </div>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% :integer -> %>
                      <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                        <label class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5"><%= humanize_config_key(key) %><%= if is_nullable_field?(key), do: " (Optional)" %></label>
                        <div class="mt-2 sm:col-span-2 sm:mt-0">
                          <input 
                            name={"database[config][#{key}]"} 
                            type="number" 
                            value={format_integer_value(get_config_value(@form, key, value))}
                            placeholder={if is_nullable_field?(key), do: "Leave empty for no expiration", else: nil}
                            class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-xs sm:text-sm/6" 
                          />
                        </div>
                      </div>
                    <% :string -> %>
                      <div class="sm:grid sm:grid-cols-3 sm:items-start sm:gap-4 sm:py-6">
                        <label class="block text-sm/6 font-medium text-gray-900 sm:pt-1.5"><%= humanize_config_key(key) %></label>
                        <div class="mt-2 sm:col-span-2 sm:mt-0">
                          <input 
                            name={"database[config][#{key}]"} 
                            type="text" 
                            value={get_config_value(@form, key, value)}
                            class="block w-full rounded-md bg-white px-3 py-1.5 text-base text-gray-900 outline-1 -outline-offset-1 outline-gray-300 placeholder:text-gray-400 focus:outline-2 focus:-outline-offset-2 focus:outline-indigo-600 sm:max-w-md sm:text-sm/6" 
                          />
                        </div>
                      </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
        
        <div class="border-t border-gray-100 px-4 py-6 sm:px-6">
          <div class="flex items-center justify-end gap-x-6">
            <button type="button" phx-click={JS.patch(~p"/admin/databases")} class="text-sm/6 font-semibold text-gray-900">Cancel</button>
            <button type="submit" phx-disable-with="Saving..." class="inline-flex justify-center rounded-md bg-indigo-600 px-3 py-2 text-sm font-semibold text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">Save Database</button>
          </div>
        </div>
      </form>
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

  defp is_nullable_field?("expire_after"), do: true
  defp is_nullable_field?(_), do: false

  defp format_integer_value(nil), do: ""
  defp format_integer_value(value) when is_integer(value), do: to_string(value)
  defp format_integer_value(value) when is_binary(value), do: value
  defp format_integer_value(_), do: ""
end