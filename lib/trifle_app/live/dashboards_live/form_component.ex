defmodule TrifleApp.DashboardsLive.FormComponent do
  use TrifleApp, :live_component

  alias Trifle.Organizations

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        New Dashboard
        <:subtitle>Create a new dashboard. You can configure details after creation.</:subtitle>
      </.header>

      <.form_container
        for={@form}
        id="dashboard-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.form_field
          field={@form[:name]}
          type="text"
          label="Name"
          placeholder="e.g., Sales Dashboard"
          required
        />

        <:actions>
          <.primary_button phx-disable-with="Creating...">Create Dashboard</.primary_button>
          <.secondary_button phx-click={JS.patch(@patch)}>Cancel</.secondary_button>
        </:actions>
      </.form_container>
    </div>
    """
  end

  def update(%{dashboard: dashboard} = assigns, socket) do
    changeset = Organizations.change_dashboard(dashboard)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  def handle_event("validate", %{"dashboard" => dashboard_params}, socket) do
    changeset =
      socket.assigns.dashboard
      |> Organizations.change_dashboard(dashboard_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"dashboard" => dashboard_params}, socket) do
    save_dashboard(socket, dashboard_params)
  end

  defp save_dashboard(socket, dashboard_params) do
    dashboard_params =
      dashboard_params
      |> Map.put("database_id", socket.assigns.database.id)
      |> Map.put("user_id", socket.assigns.current_user.id)
      # Default key
      |> Map.put("key", "dashboard")
      # Default to personal
      |> Map.put("visibility", false)
      |> Map.put("locked", false)
      |> Map.put_new("default_timeframe", socket.assigns.database.default_timeframe || "24h")
      |> Map.put_new("default_granularity", socket.assigns.database.default_granularity || "1h")

    case Organizations.create_dashboard(dashboard_params) do
      {:ok, dashboard} ->
        notify_parent({:saved, dashboard})

        {:noreply,
         socket
         |> put_flash(:info, "Dashboard created successfully")
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
