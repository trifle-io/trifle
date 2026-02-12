defmodule TrifleAdmin.BillingPlansLive.FormComponent do
  use TrifleAdmin, :live_component

  alias Phoenix.LiveView.JS
  alias Trifle.Billing

  @scope_options [{"App", "app"}, {"Project", "project"}]
  @interval_options [{"Day", "day"}, {"Week", "week"}, {"Month", "month"}, {"Year", "year"}]
  @currency_options [{"USD", "usd"}, {"EUR", "eur"}, {"GBP", "gbp"}]

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form_container for={@form} phx-target={@myself} phx-change="validate" phx-submit="save">
        <:header title={@title} subtitle="Define Stripe price mapping for app and project plans." />

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:organization_id]}
            label="Organization ID"
            help_text="Leave blank to create a global plan."
          />
          <.form_field field={@form[:name]} label="Name" required />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:scope_type]}
            type="select"
            label="Scope"
            options={@scope_options}
            prompt="Choose scope..."
          />
          <.form_field field={@form[:tier_key]} label="Tier Key" required />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:interval]}
            type="select"
            label="Interval"
            options={@interval_options}
            prompt="Choose interval..."
          />
          <.form_field field={@form[:stripe_price_id]} label="Stripe Price ID" required />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:currency]}
            type="select"
            label="Currency"
            options={@currency_options}
            prompt="Choose currency..."
          />
          <.form_field field={@form[:amount_cents]} type="number" label="Amount (cents)" />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <.form_field
            field={@form[:seat_limit]}
            type="number"
            label="Seat Limit"
            help_text="Used for app plans."
          />
          <.form_field
            field={@form[:hard_limit]}
            type="number"
            label="Hard Limit"
            help_text="Used for project plans."
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <.form_field
            field={@form[:retention_add_on]}
            type="checkbox"
            label="Retention Add-on"
            help_text="Allowed only for project plans."
          />
          <.form_field
            field={@form[:founder_offer]}
            type="checkbox"
            label="Founder Offer"
            help_text="Allowed only for app pro monthly."
          />
          <.form_field field={@form[:active]} type="checkbox" label="Active" />
        </div>

        <div class="space-y-2">
          <label class="block text-sm font-medium text-gray-700 dark:text-slate-300">
            Metadata (JSON)
          </label>
          <textarea
            name="plan[metadata_json]"
            rows="6"
            class={[
              "block w-full rounded-lg border bg-white dark:bg-slate-700 text-gray-900 dark:text-white shadow-sm focus:border-teal-500 focus:ring-teal-500 sm:text-sm",
              if(@metadata_error,
                do: "border-red-400 focus:border-red-400 focus:ring-red-400",
                else: "border-gray-300 dark:border-slate-600"
              )
            ]}
          >{@metadata_json}</textarea>
          <%= if @metadata_error do %>
            <p class="text-sm text-red-600 dark:text-red-400">{@metadata_error}</p>
          <% end %>
        </div>

        <:actions>
          <.form_actions>
            <.secondary_button type="button" phx-click={JS.patch(@patch)}>
              Cancel
            </.secondary_button>
            <.primary_button phx-disable-with="Saving...">Save Plan</.primary_button>
          </.form_actions>
        </:actions>
      </.form_container>
    </div>
    """
  end

  @impl true
  def update(%{plan: plan} = assigns, socket) do
    changeset = Billing.change_billing_plan(plan)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:title, assigns[:title] || "Billing Plan")
     |> assign(:scope_options, @scope_options)
     |> assign(:interval_options, @interval_options)
     |> assign(:currency_options, @currency_options)
     |> assign(:metadata_error, nil)
     |> assign(:metadata_json, format_metadata(plan.metadata))
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"plan" => params}, socket) do
    {attrs, metadata_json, metadata_error} = normalize_params(params)

    changeset =
      socket.assigns.plan
      |> Billing.change_billing_plan(attrs)
      |> maybe_add_metadata_error(metadata_error)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:metadata_json, metadata_json)
     |> assign(:metadata_error, metadata_error)
     |> assign_form(changeset)}
  end

  def handle_event("save", %{"plan" => params}, socket) do
    {attrs, metadata_json, metadata_error} = normalize_params(params)

    if metadata_error do
      changeset =
        socket.assigns.plan
        |> Billing.change_billing_plan(attrs)
        |> maybe_add_metadata_error(metadata_error)
        |> Map.put(:action, persist_action(socket))

      {:noreply,
       socket
       |> assign(:metadata_json, metadata_json)
       |> assign(:metadata_error, metadata_error)
       |> assign_form(changeset)}
    else
      save_plan(socket, attrs, metadata_json)
    end
  end

  defp save_plan(%{assigns: %{action: :new}} = socket, attrs, metadata_json) do
    case Billing.create_billing_plan(attrs) do
      {:ok, plan} ->
        notify_parent({:saved, plan})

        {:noreply,
         socket
         |> put_flash(:info, "Billing plan created successfully.")
         |> assign(:metadata_json, metadata_json)
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(:metadata_json, metadata_json) |> assign_form(changeset)}
    end
  end

  defp save_plan(%{assigns: %{action: :edit}} = socket, attrs, metadata_json) do
    case Billing.update_billing_plan(socket.assigns.plan, attrs) do
      {:ok, plan} ->
        notify_parent({:saved, plan})

        {:noreply,
         socket
         |> put_flash(:info, "Billing plan updated successfully.")
         |> assign(:metadata_json, metadata_json)
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(:metadata_json, metadata_json) |> assign_form(changeset)}
    end
  end

  defp normalize_params(params) do
    metadata_json =
      params
      |> Map.get("metadata_json", "{}")
      |> to_string()

    metadata_result = parse_metadata(metadata_json)

    attrs =
      params
      |> Map.drop(["metadata_json"])
      |> normalize_blank_organization()
      |> put_metadata(metadata_result)

    metadata_error =
      case metadata_result do
        {:ok, _map} -> nil
        {:error, error} -> error
      end

    {attrs, metadata_json, metadata_error}
  end

  defp normalize_blank_organization(params) do
    case Map.get(params, "organization_id") do
      nil ->
        params

      value ->
        if String.trim(value) == "" do
          Map.put(params, "organization_id", nil)
        else
          params
        end
    end
  end

  defp parse_metadata(raw) when is_binary(raw) do
    trimmed = String.trim(raw)

    cond do
      trimmed == "" ->
        {:ok, %{}}

      true ->
        case Jason.decode(trimmed) do
          {:ok, %{} = map} -> {:ok, map}
          {:ok, _non_map} -> {:error, "metadata must be a JSON object"}
          {:error, _} -> {:error, "metadata must be valid JSON"}
        end
    end
  end

  defp put_metadata(params, {:ok, metadata}), do: Map.put(params, "metadata", metadata)
  defp put_metadata(params, {:error, _}), do: Map.put(params, "metadata", %{})

  defp maybe_add_metadata_error(changeset, nil), do: changeset

  defp maybe_add_metadata_error(changeset, message),
    do: Ecto.Changeset.add_error(changeset, :metadata, message)

  defp persist_action(%{assigns: %{action: :edit}}), do: :update
  defp persist_action(_socket), do: :insert

  defp assign_form(socket, %Ecto.Changeset{} = changeset),
    do: assign(socket, :form, to_form(changeset))

  defp format_metadata(nil), do: "{}"
  defp format_metadata(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp format_metadata(_), do: "{}"

  defp notify_parent(message), do: send(self(), {__MODULE__, message})
end
