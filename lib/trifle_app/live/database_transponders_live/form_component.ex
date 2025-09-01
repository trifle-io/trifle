defmodule TrifleApp.DatabaseTranspondersLive.FormComponent do
  use TrifleApp, :live_component

  alias Trifle.Organizations
  alias Trifle.Organizations.Transponder

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Create or edit transponders to collect data from your applications.</:subtitle>
      </.header>

      <.form_container
        for={@form}
        id="transponder-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.form_field field={@form[:name]} type="text" label="Name" placeholder="e.g., Conversion Rate Calculator" />
        <.form_field field={@form[:key]} type="text" label="Key Pattern" placeholder="e.g., customer::(.*)::orders" />
        
        <div>
          <.label>Type</.label>
          <div class="grid grid-cols-1 sm:max-w-xs mt-2">
            <select 
              id="transponder_type"
              name="transponder[type]" 
              phx-change="select_type" 
              phx-target={@myself}
              disabled={@action == :edit}
              class={[
                "col-start-1 row-start-1 w-full appearance-none rounded-md py-1.5 pr-8 pl-3 text-base outline-1 -outline-offset-1 focus:outline-2 focus:-outline-offset-2 sm:text-sm/6",
                if(@action == :edit, 
                  do: "bg-gray-50 text-gray-500 cursor-not-allowed outline-gray-200", 
                  else: "bg-white text-gray-900 outline-gray-300 focus:outline-teal-600")
              ]}
            >
              <option value="">Select transponder type...</option>
              <%= for type <- Transponder.available_types() do %>
                <option value={type} selected={@selected_type == type}>
                  <%= Transponder.get_type_display_name(type) %>
                </option>
              <% end %>
            </select>
            <svg viewBox="0 0 16 16" fill="currentColor" data-slot="icon" aria-hidden="true" class="pointer-events-none col-start-1 row-start-1 mr-2 h-5 w-5 self-center justify-self-end text-gray-500 sm:h-4 sm:w-4">
              <path d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" fill-rule="evenodd" />
            </svg>
          </div>
        </div>

        <%= if @selected_type do %>
          <%= for field <- Transponder.get_transponder_fields(@selected_type) do %>
            <div>
              <.label>
                <%= field.label %>
                <%= if field.required do %><span class="text-red-500">*</span><% end %>
              </.label>
              <input
                type="text"
                name={"transponder[config][#{field.name}]"}
                value={@config_values[field.name] || @config_values[String.to_atom(field.name)] || ""}
                class="mt-2 block w-full rounded-md border-0 py-1.5 pl-3 pr-3 text-gray-900 ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6"
                placeholder={field.label}
                required={field.required}
              />
            </div>
          <% end %>
        <% end %>

        <:actions>
          <.form_actions>
            <.primary_button phx-disable-with="Saving..." class="bg-teal-600 hover:bg-teal-500">
              <%= if @action == :new, do: "Create Transponder", else: "Update Transponder" %>
            </.primary_button>
          </.form_actions>
        </:actions>
      </.form_container>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(%{transponder: transponder} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:selected_type, transponder.type)
     |> assign(:config_values, transponder.config || %{})
     |> assign_form(Organizations.change_transponder(transponder))}
  end

  def handle_event("validate", %{"transponder" => transponder_params}, socket) do
    config_values = Map.get(transponder_params, "config", %{})
    
    # Only validate the basic fields, preserve config values in component state
    basic_params = Map.drop(transponder_params, ["config"])
    
    changeset =
      socket.assigns.transponder
      |> Organizations.change_transponder(basic_params)
      |> Map.put(:action, :validate)

    {:noreply, 
     socket
     |> assign(:config_values, Map.merge(socket.assigns.config_values, config_values))
     |> assign_form(changeset)}
  end

  def handle_event("select_type", %{"transponder" => %{"type" => type}}, socket) when type != "" do
    {:noreply, assign(socket, :selected_type, type)}
  end

  def handle_event("select_type", _params, socket) do
    {:noreply, assign(socket, :selected_type, nil)}
  end

  def handle_event("save", %{"transponder" => transponder_params}, socket) do
    # Get config from the form submission and merge with component state
    form_config = Map.get(transponder_params, "config", %{})
    merged_config = Map.merge(socket.assigns.config_values, form_config)
    
    # Filter out empty values from config
    clean_config = Enum.reject(merged_config, fn {_k, v} -> v == "" or is_nil(v) end) |> Map.new()
    
    transponder_params = Map.put(transponder_params, "config", clean_config)
    save_transponder(socket, socket.assigns.action, transponder_params)
  end

  defp save_transponder(socket, :edit, transponder_params) do
    case Organizations.update_transponder(socket.assigns.transponder, transponder_params) do
      {:ok, transponder} ->
        notify_parent({:updated, transponder})

        {:noreply,
         socket
         |> put_flash(:info, "Transponder updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_transponder(socket, :new, transponder_params) do
    # Set the order for new transponders
    next_order = Organizations.get_next_transponder_order(socket.assigns.database)
    
    transponder_params = 
      transponder_params
      |> Map.put("database_id", socket.assigns.database.id)
      |> Map.put("order", next_order)

    case Organizations.create_transponder(transponder_params) do
      {:ok, transponder} ->
        notify_parent({:saved, transponder})

        {:noreply,
         socket
         |> put_flash(:info, "Transponder created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})

end