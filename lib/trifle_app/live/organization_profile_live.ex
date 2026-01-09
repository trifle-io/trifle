defmodule TrifleApp.OrganizationProfileLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.{Organization, OrganizationMembership}

  alias TrifleApp.OrganizationLive.Navigation

  @countries [
    {"United States", "US"},
    {"Canada", "CA"},
    {"United Kingdom", "GB"},
    {"Germany", "DE"},
    {"France", "FR"},
    {"Spain", "ES"},
    {"Italy", "IT"},
    {"Netherlands", "NL"},
    {"Sweden", "SE"},
    {"Norway", "NO"},
    {"Denmark", "DK"},
    {"Finland", "FI"},
    {"Australia", "AU"},
    {"New Zealand", "NZ"},
    {"Brazil", "BR"},
    {"Mexico", "MX"},
    {"Japan", "JP"},
    {"Singapore", "SG"},
    {"India", "IN"},
    {"Other", "OTHER"}
  ]

  @us_states [
    {"Alabama", "AL"},
    {"Alaska", "AK"},
    {"Arizona", "AZ"},
    {"Arkansas", "AR"},
    {"California", "CA"},
    {"Colorado", "CO"},
    {"Connecticut", "CT"},
    {"Delaware", "DE"},
    {"District of Columbia", "DC"},
    {"Florida", "FL"},
    {"Georgia", "GA"},
    {"Hawaii", "HI"},
    {"Idaho", "ID"},
    {"Illinois", "IL"},
    {"Indiana", "IN"},
    {"Iowa", "IA"},
    {"Kansas", "KS"},
    {"Kentucky", "KY"},
    {"Louisiana", "LA"},
    {"Maine", "ME"},
    {"Maryland", "MD"},
    {"Massachusetts", "MA"},
    {"Michigan", "MI"},
    {"Minnesota", "MN"},
    {"Mississippi", "MS"},
    {"Missouri", "MO"},
    {"Montana", "MT"},
    {"Nebraska", "NE"},
    {"Nevada", "NV"},
    {"New Hampshire", "NH"},
    {"New Jersey", "NJ"},
    {"New Mexico", "NM"},
    {"New York", "NY"},
    {"North Carolina", "NC"},
    {"North Dakota", "ND"},
    {"Ohio", "OH"},
    {"Oklahoma", "OK"},
    {"Oregon", "OR"},
    {"Pennsylvania", "PA"},
    {"Rhode Island", "RI"},
    {"South Carolina", "SC"},
    {"South Dakota", "SD"},
    {"Tennessee", "TN"},
    {"Texas", "TX"},
    {"Utah", "UT"},
    {"Vermont", "VT"},
    {"Virginia", "VA"},
    {"Washington", "WA"},
    {"West Virginia", "WV"},
    {"Wisconsin", "WI"},
    {"Wyoming", "WY"}
  ]

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Profile")
      |> assign(:breadcrumb_links, Navigation.breadcrumb(:profile))
      |> assign(:active_tab, :profile)
      |> assign(:current_user, current_user)
      |> assign(:show_profile_modal, false)

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok,
         socket
         |> assign(:current_membership, nil)
         |> assign(:organization, nil)
         |> assign(:can_manage, true)
         |> assign(
           :organization_form,
           to_form(Organizations.change_organization(%Organization{}))
         )}

      true ->
        {:ok, load_profile_state(socket, membership)}
    end
  end

  def handle_event("open_profile_modal", _params, %{assigns: %{can_manage: true}} = socket) do
    {:noreply, assign(socket, :show_profile_modal, true)}
  end

  def handle_event("open_profile_modal", _params, socket), do: {:noreply, socket}

  def handle_event("close_profile_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_profile_modal, false)
      |> maybe_reset_profile_form()

    {:noreply, socket}
  end

  def handle_event(
        "change_profile",
        %{"organization" => params},
        %{assigns: %{organization: %Organization{} = organization, can_manage: true}} = socket
      ) do
    changeset =
      organization
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :organization_form, to_form(changeset))}
  end

  def handle_event("change_profile", _params, socket), do: {:noreply, socket}

  def handle_event(
        "save_profile",
        %{"organization" => params},
        %{
          assigns: %{organization: %Organization{} = organization, current_membership: membership}
        } = socket
      ) do
    if Organizations.membership_admin?(membership) do
      case Organizations.update_organization(organization, params) do
        {:ok, updated} ->
          updated_membership = %{membership | organization: updated}

          {:noreply,
           socket
           |> assign(:organization, updated)
           |> assign(:current_membership, updated_membership)
           |> assign(:organization_form, to_form(Organizations.change_organization(updated)))
           |> assign(:show_profile_modal, false)
           |> put_flash(:info, "Organization profile updated")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :organization_form, to_form(changeset))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_profile", _params, socket), do: {:noreply, socket}

  def handle_event(
        "create_organization",
        %{"organization" => params},
        %{assigns: %{current_user: user}} = socket
      ) do
    case Organizations.create_organization_with_owner(params, user) do
      {:ok, organization, membership} ->
        membership = %{membership | organization: organization}

        {:noreply,
         socket
         |> assign(:current_membership, membership)
         |> load_profile_state(membership)
         |> put_flash(:info, "Organization created. You are the owner by default.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :organization_form, to_form(changeset))}

      {:error, :already_member} ->
        {:noreply, socket |> put_flash(:error, "You already belong to an organization")}

      {:error, reason} ->
        {:noreply,
         socket |> put_flash(:error, "Failed to create organization: #{inspect(reason)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <%= if @current_membership do %>
        <Navigation.nav active_tab={@active_tab} />
        <.profile_section
          organization={@organization}
          organization_form={@organization_form}
          can_manage={@can_manage}
          show_profile_modal={@show_profile_modal}
        />
      <% else %>
        <.setup_section organization_form={@organization_form} />
      <% end %>
    </div>
    """
  end

  defp load_profile_state(socket, %OrganizationMembership{} = membership) do
    organization =
      membership.organization || Organizations.get_organization!(membership.organization_id)

    socket
    |> assign(:current_membership, membership)
    |> assign(:organization, organization)
    |> assign(:can_manage, Organizations.membership_admin?(membership))
    |> assign(:organization_form, to_form(Organizations.change_organization(organization)))
    |> assign(:breadcrumb_links, Navigation.breadcrumb(:profile))
    |> assign(:page_title, "Organization · Profile")
    |> assign(:show_profile_modal, false)
  end

  defp maybe_reset_profile_form(
         %Phoenix.LiveView.Socket{assigns: %{organization: %Organization{} = organization}} =
           socket
       ) do
    assign(socket, :organization_form, to_form(Organizations.change_organization(organization)))
  end

  defp maybe_reset_profile_form(socket), do: socket

  defp country_options, do: @countries
  defp us_state_options, do: @us_states

  defp value_to_string(nil), do: ""
  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value), do: to_string(value)

  defp default_country(value) when value in ["", "nil", nil], do: "US"
  defp default_country(value), do: value

  defp us_state_name(nil), do: nil
  defp us_state_name(""), do: nil

  defp us_state_name(code) do
    uppercase = String.upcase(code)

    case Enum.find(@us_states, fn {_label, value} -> value == uppercase end) do
      {label, _} -> label
      nil -> code
    end
  end

  defp organization_address_lines(nil), do: []

  defp organization_address_lines(%Organization{} = organization) do
    [organization.address_line1, organization.address_line2]
    |> Enum.reject(&blank?/1)
  end

  defp state_value_for_line(%Organization{country: "US", state: state}) do
    us_state_name(state)
  end

  defp state_value_for_line(%Organization{state: state}), do: state

  defp formatted_state(%Organization{} = organization) do
    value = state_value_for_line(organization)

    if blank?(value), do: "—", else: value
  end

  defp registration_country_label(nil), do: "—"

  defp registration_country_label(%Organization{} = organization) do
    code = organization.country |> value_to_string() |> String.upcase()
    if blank?(code), do: "—", else: code
  end

  defp address_country_value(%Organization{} = organization) do
    organization.address_country || Map.get(organization.metadata || %{}, "address_country") ||
      organization.country
  end

  defp address_country_label(nil), do: "—"

  defp address_country_label(%Organization{} = organization) do
    code = address_country_value(organization) |> value_to_string() |> String.upcase()
    if blank?(code), do: "—", else: code
  end

  defp present(value) when is_binary(value), do: if(blank?(value), do: "—", else: value)
  defp present(nil), do: "—"
  defp present(value), do: value

  defp blank?(value) when is_nil(value), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  attr :organization, Organization
  attr :organization_form, :map
  attr :can_manage, :boolean
  attr :show_profile_modal, :boolean, default: false

  defp profile_section(assigns) do
    organization = assigns.organization
    registration_country_value = assigns.organization_form[:country].value
    address_country_field = assigns.organization_form[:address_country]

    address_country_value =
      if address_country_field, do: address_country_field.value, else: registration_country_value

    selected_address_country =
      address_country_value
      |> value_to_string()
      |> default_country()

    state_select? = selected_address_country == "US"

    assigns =
      assigns
      |> assign(:address_lines, organization_address_lines(organization))
      |> assign(:country_options, country_options())
      |> assign(:state_options, if(state_select?, do: us_state_options(), else: []))
      |> assign(:state_select?, state_select?)

    ~H"""
    <div class="bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg p-6">
      <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 mb-6">
        <div>
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Organization details</h2>
          <p class="text-sm text-gray-500 dark:text-slate-400">
            Review key information about your organization.
          </p>
        </div>
        <%= if @can_manage and @organization do %>
          <button
            type="button"
            phx-click="open_profile_modal"
            class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
          >
            Edit details
          </button>
        <% end %>
      </div>

      <%= if @organization do %>
        <dl class="grid grid-cols-1 gap-y-6 gap-x-8 sm:grid-cols-2">
          <div class="space-y-6">
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                Organization name
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {present(@organization.name)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                Registration number
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {present(@organization.registration_number)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                VAT number
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {present(@organization.vat_number)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                Registration country
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {registration_country_label(@organization)}
              </dd>
            </div>
          </div>
          <div class="space-y-6">
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                Address
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                <address class="not-italic space-y-1">
                  <%= if @address_lines == [] do %>
                    <span>—</span>
                  <% else %>
                    <%= for line <- @address_lines do %>
                      <div>{line}</div>
                    <% end %>
                  <% end %>
                </address>
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                City
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {present(@organization.city)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                Postal code
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {present(@organization.postal_code)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                State / Region
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {formatted_state(@organization)}
              </dd>
            </div>
            <div>
              <dt class="text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-slate-400">
                Address country
              </dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                {address_country_label(@organization)}
              </dd>
            </div>
          </div>
        </dl>
      <% else %>
        <p class="text-sm text-gray-500 dark:text-slate-400">
          Organization details will appear here once configured.
        </p>
      <% end %>

      <.app_modal
        id="edit-organization"
        show={@show_profile_modal}
        on_cancel="close_profile_modal"
        size="lg"
      >
        <:title>Edit organization</:title>
        <:body>
          <.form
            for={@organization_form}
            phx-submit="save_profile"
            phx-change="change_profile"
            class="space-y-6"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="space-y-4">
                <.form_field
                  type="text"
                  field={@organization_form[:name]}
                  label="Organization name"
                  required
                />
                <.form_field
                  type="text"
                  field={@organization_form[:registration_number]}
                  label="Registration number"
                />
                <.form_field type="text" field={@organization_form[:vat_number]} label="VAT number" />
                <.form_field
                  type="select"
                  field={@organization_form[:country]}
                  label="Registration country"
                  options={@country_options}
                  prompt="Select country"
                />
              </div>
              <div class="space-y-4">
                <.form_field
                  type="text"
                  field={@organization_form[:address_line1]}
                  label="Address line 1"
                />
                <.form_field
                  type="text"
                  field={@organization_form[:address_line2]}
                  label="Address line 2"
                />
                <.form_field type="text" field={@organization_form[:city]} label="City" />
                <.form_field type="text" field={@organization_form[:postal_code]} label="Postal code" />
                <%= if @state_select? do %>
                  <.form_field
                    type="select"
                    field={@organization_form[:state]}
                    label="State"
                    options={@state_options}
                    prompt="Select state"
                  />
                <% else %>
                  <.form_field type="text" field={@organization_form[:state]} label="State / Region" />
                <% end %>
                <.form_field
                  type="select"
                  field={@organization_form[:address_country]}
                  label="Address country"
                  options={@country_options}
                  prompt="Select country"
                />
              </div>
            </div>

            <.form_actions spacing="gap-2">
              <.secondary_button type="button" phx-click="close_profile_modal">
                Cancel
              </.secondary_button>
              <.primary_button phx-disable-with="Saving...">Save changes</.primary_button>
            </.form_actions>
          </.form>
        </:body>
      </.app_modal>
    </div>
    """
  end

  attr :organization_form, :map

  defp setup_section(assigns) do
    assigns = assign(assigns, :country_options, country_options())

    ~H"""
    <div class="max-w-xl mx-auto bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg p-6 mt-8">
      <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">
        Create your organization
      </h2>
      <p class="text-sm text-gray-600 dark:text-slate-300 mb-4">
        Get started by naming your organization. You will become the owner and can invite teammates afterwards.
      </p>
      <.form for={@organization_form} phx-submit="create_organization" class="space-y-4">
        <.form_field
          type="text"
          field={@organization_form[:name]}
          label="Organization name"
          required={true}
        />
        <.form_field
          type="select"
          field={@organization_form[:country]}
          label="Registration country"
          options={@country_options}
          prompt="Select country"
        />
        <.form_actions>
          <.primary_button phx-disable-with="Creating...">Create organization</.primary_button>
        </.form_actions>
      </.form>
    </div>
    """
  end
end
