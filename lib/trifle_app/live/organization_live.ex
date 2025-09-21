defmodule TrifleApp.OrganizationLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.{Organization, OrganizationInvitation, OrganizationMembership}

  @tabs [:profile, :users, :invitations, :billing]

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
    {"Alabama", "AL"}, {"Alaska", "AK"}, {"Arizona", "AZ"}, {"Arkansas", "AR"},
    {"California", "CA"}, {"Colorado", "CO"}, {"Connecticut", "CT"}, {"Delaware", "DE"},
    {"District of Columbia", "DC"}, {"Florida", "FL"}, {"Georgia", "GA"}, {"Hawaii", "HI"},
    {"Idaho", "ID"}, {"Illinois", "IL"}, {"Indiana", "IN"}, {"Iowa", "IA"},
    {"Kansas", "KS"}, {"Kentucky", "KY"}, {"Louisiana", "LA"}, {"Maine", "ME"},
    {"Maryland", "MD"}, {"Massachusetts", "MA"}, {"Michigan", "MI"}, {"Minnesota", "MN"},
    {"Mississippi", "MS"}, {"Missouri", "MO"}, {"Montana", "MT"}, {"Nebraska", "NE"},
    {"Nevada", "NV"}, {"New Hampshire", "NH"}, {"New Jersey", "NJ"}, {"New Mexico", "NM"},
    {"New York", "NY"}, {"North Carolina", "NC"}, {"North Dakota", "ND"}, {"Ohio", "OH"},
    {"Oklahoma", "OK"}, {"Oregon", "OR"}, {"Pennsylvania", "PA"}, {"Rhode Island", "RI"},
    {"South Carolina", "SC"}, {"South Dakota", "SD"}, {"Tennessee", "TN"}, {"Texas", "TX"},
    {"Utah", "UT"}, {"Vermont", "VT"}, {"Virginia", "VA"}, {"Washington", "WA"},
    {"West Virginia", "WV"}, {"Wisconsin", "WI"}, {"Wyoming", "WY"}
  ]

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:current_membership, membership)
      |> assign(:current_user, current_user)
      |> assign(:deployment_mode, deployment_mode())
      |> assign(:roles, Organizations.membership_roles())
      |> assign(:show_profile_modal, false)

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok,
         socket
         |> assign(:active_tab, :setup)
         |> assign(:organization, nil)
         |> assign(:members, [])
         |> assign(:invitations, [])
         |> assign(:can_manage, true)
         |> assign(:organization_form, to_form(Organizations.change_organization(%Organization{})))
         |> assign(:invitation_form, nil)
         |> assign(:show_profile_modal, false)}

      true ->
        {:ok, load_organization_state(socket, membership)}
    end
  end

  defp maybe_reset_profile_form(%Phoenix.LiveView.Socket{assigns: %{organization: %Organization{} = organization}} = socket) do
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

  defp country_label(nil), do: "—"
  defp country_label(""), do: "—"
  defp country_label(code) do
    case Enum.find(@countries, fn {_label, value} -> value == code end) do
      {label, _} -> label
      nil -> code
    end
  end

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

    if blank?(value) do
      "—"
    else
      value
    end
  end

  defp registration_country_label(nil), do: "—"
  defp registration_country_label(%Organization{} = organization) do
    code = organization.country |> value_to_string() |> String.upcase()
    if blank?(code), do: "—", else: code
  end

  defp address_country_label(nil), do: "—"
  defp address_country_label(%Organization{} = organization) do
    code = address_country_value(organization) |> value_to_string() |> String.upcase()
    if blank?(code), do: "—", else: code
  end

  defp address_country_value(nil), do: nil
  defp address_country_value(%Organization{} = organization) do
    organization.address_country || Map.get(organization.metadata || %{}, "address_country") || organization.country
  end

  defp present(value) when is_binary(value), do: if(blank?(value), do: "—", else: value)
  defp present(nil), do: "—"
  defp present(value), do: value

  defp blank?(value) when is_nil(value), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  def handle_params(%{"tab" => tab_param}, _uri, %{assigns: %{current_membership: %OrganizationMembership{}}} = socket) do
    tab = parse_tab(tab_param)
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
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

  def handle_event("change_profile", %{"organization" => params}, %{assigns: %{organization: %Organization{} = organization, can_manage: true}} = socket) do
    changeset =
      organization
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :organization_form, to_form(changeset))}
  end

  def handle_event("change_profile", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <%= if @current_membership do %>
        <div class="mb-6 border-b border-gray-200 dark:border-slate-700">
          <nav class="-mb-px flex flex-wrap gap-4" aria-label="Organization tabs">
            <.link navigate={~p"/app/organization?tab=profile"} class={tab_link_classes(@active_tab == :profile)}>
              <svg class={tab_icon_classes(@active_tab == :profile)} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M20.25 14.15v4.25c0 1.094-.787 2.036-1.872 2.18-2.087.277-4.216.42-6.378.42s-4.291-.143-6.378-.42c-1.085-.144-1.872-1.086-1.872-2.18v-4.25m16.5 0a2.18 2.18 0 0 0 .75-1.661V8.706c0-1.081-.768-2.015-1.837-2.175a48.114 48.114 0 0 0-3.413-.387m4.5 8.006c-.194.165-.42.295-.673.38A23.978 23.978 0 0 1 12 15.75c-2.648 0-5.195-.429-7.577-1.22a2.016 2.016 0 0 1-.673-.38m0 0A2.18 2.18 0 0 1 3 12.489V8.706c0-1.081.768-2.015 1.837-2.175a48.111 48.111 0 0 1 3.413-.387m7.5 0V5.25A2.25 2.25 0 0 0 13.5 3h-3a2.25 2.25 0 0 0-2.25 2.25v.894m7.5 0a48.667 48.667 0 0 0-7.5 0M12 12.75h.008v.008H12v-.008Z" />
              </svg>
              <span class="hidden sm:block">Profile</span>
            </.link>

            <.link navigate={~p"/app/organization?tab=users"} class={tab_link_classes(@active_tab == :users)}>
              <svg class={tab_icon_classes(@active_tab == :users)} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M18 18.72a9.094 9.094 0 0 0 3.741-.479 3 3 0 0 0-4.682-2.72m.94 3.198.001.031c0 .225-.012.447-.037.666A11.944 11.944 0 0 1 12 21c-2.17 0-4.207-.576-5.963-1.584A6.062 6.062 0 0 1 6 18.719m12 0a5.971 5.971 0 0 0-.941-3.197m0 0A5.995 5.995 0 0 0 12 12.75a5.995 5.995 0 0 0-5.058 2.772m0 0a3 3 0 0 0-4.681 2.72 8.986 8.986 0 0 0 3.74.477m.94-3.197a5.971 5.971 0 0 0-.94 3.197M15 6.75a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm6 3a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm-13.5 0a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z" />
              </svg>
              <span class="hidden sm:block">Users</span>
            </.link>

            <.link navigate={~p"/app/organization?tab=invitations"} class={tab_link_classes(@active_tab == :invitations)}>
              <svg class={tab_icon_classes(@active_tab == :invitations)} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M18 7.5v3m0 0v3m0-3h3m-3 0h-3m-2.25-4.125a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0ZM3 19.235v-.11a6.375 6.375 0 0 1 12.75 0v.109A12.318 12.318 0 0 1 9.374 21c-2.331 0-4.512-.645-6.374-1.766Z" />
              </svg>
              <span class="hidden sm:block">Invitations</span>
            </.link>

            <.link navigate={~p"/app/organization?tab=billing"} class={tab_link_classes(@active_tab == :billing, :right)}>
              <svg class={tab_icon_classes(@active_tab == :billing)} xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" d="M2.25 18.75a60.07 60.07 0 0 1 15.797 2.101c.727.198 1.453-.342 1.453-1.096V18.75M3.75 4.5v.75A.75.75 0 0 1 3 6h-.75m0 0v-.375c0-.621.504-1.125 1.125-1.125H20.25M2.25 6v9m18-10.5v.75c0 .414.336.75.75.75h.75m-1.5-1.5h.375c.621 0 1.125.504 1.125 1.125v9.75c0 .621-.504 1.125-1.125 1.125h-.375m1.5-1.5H21a.75.75 0 0 0-.75.75v.75m0 0H3.75m0 0h-.375a1.125 1.125 0 0 1-1.125-1.125V15m1.5 1.5v-.75A.75.75 0 0 0 3 15h-.75M15 10.5a3 3 0 1 1-6 0 3 3 0 0 1 6 0Zm3 0h.008v.008H18V10.5Zm-12 0h.008v.008H6V10.5Z" />
              </svg>
              <span class="hidden sm:block">Billing</span>
            </.link>
          </nav>
        </div>

        <%= case @active_tab do %>
          <% :profile -> %>
            <.profile_section
              organization={@organization}
              organization_form={@organization_form}
              can_manage={@can_manage}
              show_profile_modal={@show_profile_modal}
            />
          <% :users -> %>
            <.users_section members={@members} current_membership={@current_membership} can_manage={@can_manage} roles={@roles} />
          <% :invitations -> %>
            <.invitations_section invitations={@invitations} invitation_form={@invitation_form} can_manage={@can_manage} roles={@roles} />
          <% :billing -> %>
            <.billing_section deployment_mode={@deployment_mode} />
        <% end %>
      <% else %>
        <.setup_section organization_form={@organization_form} />
      <% end %>
    </div>
    """
  end

  def handle_event("save_profile", %{"organization" => params}, %{assigns: %{organization: %Organization{} = organization, current_membership: membership}} = socket) do
    if socket.assigns.can_manage do
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

  def handle_event("update_role", %{"id" => member_id, "role" => role}, socket) do
    %{assigns: %{members: members, current_membership: current_membership}} = socket

    with true <- socket.assigns.can_manage,
         %OrganizationMembership{} = target <- Enum.find(members, &(&1.id == member_id)),
         false <- target.id == current_membership.id and role != target.role,
         :ok <- ensure_owner_count_allows_role_change(members, target, role) do
      case Organizations.update_membership_role(target, role) do
        {:ok, _membership} ->
          {:noreply, refresh_members(socket, "Role updated")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, socket |> put_flash(:error, changeset_error_message(changeset))}
      end
    else
      false -> {:noreply, socket |> put_flash(:error, "You cannot change your own role this way")}
      {:error, :last_owner} -> {:noreply, socket |> put_flash(:error, "An organization must have at least one owner")}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("remove_member", %{"id" => member_id}, socket) do
    %{assigns: %{members: members, current_membership: current_membership}} = socket

    with true <- socket.assigns.can_manage,
         %OrganizationMembership{} = target <- Enum.find(members, &(&1.id == member_id)),
         false <- target.id == current_membership.id,
         :ok <- ensure_owner_count_allows_removal(members, target) do
      case Organizations.remove_member(target) do
        {:ok, _} -> {:noreply, refresh_members(socket, "Member removed")}
        {:error, _} -> {:noreply, socket |> put_flash(:error, "Failed to remove member")}
      end
    else
      false -> {:noreply, socket |> put_flash(:error, "You cannot remove yourself")}
      {:error, :last_owner} -> {:noreply, socket |> put_flash(:error, "An organization must have at least one owner")}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("invite_member", %{"invitation" => params}, %{assigns: %{organization: %Organization{} = organization, current_user: user}} = socket) do
    role = Map.get(params, "role", "member")
    params = Map.put(params, "role", role)

    case Organizations.create_invitation(organization, params, user) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> refresh_invitations("Invitation sent. The link expires in 3 days.")
         |> assign(:invitation_form, empty_invitation_form(organization))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :invitation_form, to_form(changeset))}
    end
  end

  def handle_event("resend_invitation", %{"id" => invitation_id}, socket) do
    with %OrganizationInvitation{} = invitation <- find_invitation(socket.assigns.invitations, invitation_id),
         {:ok, _} <- Organizations.refresh_invitation(invitation) do
      {:noreply, refresh_invitations(socket, "Invitation refreshed for another 3 days." )}
    else
      _ -> {:noreply, socket |> put_flash(:error, "Could not refresh invitation")}
    end
  end

  def handle_event("cancel_invitation", %{"id" => invitation_id}, socket) do
    with %OrganizationInvitation{} = invitation <- find_invitation(socket.assigns.invitations, invitation_id),
         {:ok, _} <- Organizations.cancel_invitation(invitation) do
      {:noreply, refresh_invitations(socket, "Invitation cancelled")}
    else
      _ -> {:noreply, socket |> put_flash(:error, "Could not cancel invitation")}
    end
  end

  def handle_event("create_organization", %{"organization" => params}, %{assigns: %{current_user: user}} = socket) do
    case Organizations.create_organization_with_owner(params, user) do
      {:ok, organization, membership} ->
        membership = %{membership | organization: organization}

        {:noreply,
         socket
         |> assign(:current_membership, membership)
         |> assign(:organization, organization)
         |> assign(:active_tab, :profile)
         |> load_organization_state(membership)
         |> put_flash(:info, "Organization created. You are the owner by default.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :organization_form, to_form(changeset))}

      {:error, :already_member} ->
        {:noreply, socket |> put_flash(:error, "You already belong to an organization")}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, "Failed to create organization: #{inspect(reason)}")}
    end
  end

  defp load_organization_state(socket, %OrganizationMembership{} = membership) do
    organization = membership.organization || Organizations.get_organization!(membership.organization_id)

    socket
    |> assign(:active_tab, socket.assigns[:active_tab] || :profile)
    |> assign(:organization, organization)
    |> assign(:current_membership, membership)
    |> assign(:members, Organizations.list_members(organization))
    |> assign(:invitations, Organizations.list_invitations(organization))
    |> assign(:can_manage, Organizations.membership_admin?(membership))
    |> assign(:organization_form, to_form(Organizations.change_organization(organization)))
    |> assign(:invitation_form, empty_invitation_form(organization))
    |> assign(:show_profile_modal, false)
  end

  defp empty_invitation_form(%Organization{} = organization) do
    %OrganizationInvitation{organization_id: organization.id}
    |> OrganizationInvitation.changeset(%{})
    |> to_form()
  end

  defp refresh_members(socket, message) do
    members = Organizations.list_members(socket.assigns.organization)
    socket
    |> assign(:members, members)
    |> put_flash(:info, message)
  end

  defp refresh_invitations(socket, message) do
    invitations = Organizations.list_invitations(socket.assigns.organization)
    socket
    |> assign(:invitations, invitations)
    |> put_flash(:info, message)
  end

  defp find_invitation(invitations, id) do
    Enum.find(invitations, &(&1.id == id))
  end

  defp ensure_owner_count_allows_role_change(members, target, new_role) do
    current_owner_count = Enum.count(members, &(&1.role == "owner"))

    cond do
      target.role == "owner" and new_role != "owner" and current_owner_count <= 1 ->
        {:error, :last_owner}

      true ->
        :ok
    end
  end

  defp ensure_owner_count_allows_removal(members, target) do
    if target.role == "owner" and Enum.count(members, &(&1.role == "owner")) <= 1 do
      {:error, :last_owner}
    else
      :ok
    end
  end

  defp changeset_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end

  defp parse_tab("profile"), do: :profile
  defp parse_tab("users"), do: :users
  defp parse_tab("invitations"), do: :invitations
  defp parse_tab("billing"), do: :billing
  defp parse_tab(_), do: :profile

  defp deployment_mode do
    Application.get_env(:trifle, :deployment_mode, :saas)
  end

  attr :organization, Organization
  attr :organization_form, :map
  attr :can_manage, :boolean
  attr :show_profile_modal, :boolean, default: false

  defp profile_section(assigns) do
    organization = assigns.organization
    registration_country_value = assigns.organization_form[:country].value
    address_country_field = assigns.organization_form[:address_country]
    address_country_value = if address_country_field, do: address_country_field.value, else: registration_country_value

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
          <p class="text-sm text-gray-500 dark:text-slate-400">Review key information about your organization.</p>
        </div>
        <%= if @can_manage and @organization do %>
          <.ghost_button type="button" phx-click="open_profile_modal">
            Edit details
          </.ghost_button>
        <% end %>
      </div>

      <%= if @organization do %>
        <dl class="grid grid-cols-1 gap-y-6 gap-x-8 sm:grid-cols-2">
          <div class="space-y-6">
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Organization name</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= present(@organization.name) %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Registration number</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= present(@organization.registration_number) %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">VAT number</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= present(@organization.vat_number) %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Registration country</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= registration_country_label(@organization) %></dd>
            </div>
          </div>
          <div class="space-y-6">
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Address</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white">
                <address class="not-italic space-y-1">
                  <%= if @address_lines == [] do %>
                    <span>—</span>
                  <% else %>
                    <%= for line <- @address_lines do %>
                      <div><%= line %></div>
                    <% end %>
                  <% end %>
                </address>
              </dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">City</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= present(@organization.city) %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Postal code</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= present(@organization.postal_code) %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">State / Region</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= formatted_state(@organization) %></dd>
            </div>
            <div>
              <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">Address country</dt>
              <dd class="mt-1 text-sm text-gray-900 dark:text-white"><%= address_country_label(@organization) %></dd>
            </div>
          </div>
        </dl>
      <% else %>
        <p class="text-sm text-gray-500 dark:text-slate-400">Organization details will appear here once configured.</p>
      <% end %>

      <.app_modal id="edit-organization" show={@show_profile_modal} on_cancel="close_profile_modal" size="lg">
        <:title>Edit organization</:title>
        <:body>
          <.form for={@organization_form} phx-submit="save_profile" phx-change="change_profile" class="space-y-6">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div class="space-y-4">
                <.form_field type="text" field={@organization_form[:name]} label="Organization name" required />
                <.form_field type="text" field={@organization_form[:registration_number]} label="Registration number" />
                <.form_field type="text" field={@organization_form[:vat_number]} label="VAT number" />
                <.form_field type="select" field={@organization_form[:country]} label="Registration country" options={@country_options} prompt="Select country" />
              </div>
              <div class="space-y-4">
                <.form_field type="text" field={@organization_form[:address_line1]} label="Address line 1" />
                <.form_field type="text" field={@organization_form[:address_line2]} label="Address line 2" />
                <.form_field type="text" field={@organization_form[:city]} label="City" />
                <.form_field type="text" field={@organization_form[:postal_code]} label="Postal code" />
                <%= if @state_select? do %>
                  <.form_field type="select" field={@organization_form[:state]} label="State" options={@state_options} prompt="Select state" />
                <% else %>
                  <.form_field type="text" field={@organization_form[:state]} label="State / Region" />
                <% end %>
                <.form_field type="select" field={@organization_form[:address_country]} label="Address country" options={@country_options} prompt="Select country" />
              </div>
            </div>

            <.form_actions spacing="gap-2">
              <.ghost_button type="button" phx-click="close_profile_modal">Cancel</.ghost_button>
              <.primary_button phx-disable-with="Saving...">Save changes</.primary_button>
            </.form_actions>
          </.form>
        </:body>
      </.app_modal>
    </div>
    """
  end

  attr :members, :list
  attr :current_membership, OrganizationMembership
  attr :can_manage, :boolean
  attr :roles, :list

  defp users_section(assigns) do
    ~H"""
    <div class="bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg">
      <div class="px-6 py-4 border-b border-gray-200 dark:border-slate-700 flex items-center justify-between">
        <div>
          <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Users</h2>
          <p class="text-sm text-gray-500 dark:text-slate-400">Manage organization members and their roles.</p>
        </div>
      </div>
      <div class="divide-y divide-gray-200 dark:divide-slate-700">
        <%= for member <- @members do %>
          <div class="px-6 py-4 flex items-center justify-between">
            <div>
              <div class="text-sm font-medium text-gray-900 dark:text-white">
                <%= member.user.email %>
                <%= if member.id == @current_membership.id do %>
                  <span class="ml-2 inline-flex items-center rounded-full bg-teal-100 px-2 py-0.5 text-xs font-medium text-teal-800">You</span>
                <% end %>
              </div>
              <div class="text-xs text-gray-500 dark:text-slate-400">
                Last active: <%= last_active_label(member.last_active_at) %>
              </div>
            </div>
            <div class="flex items-center gap-3">
              <%= if @can_manage and member.id != @current_membership.id do %>
                <label class="text-xs text-gray-500 dark:text-slate-400">Role</label>
                <select class="block w-32 rounded-md border-gray-300 dark:border-slate-700 text-sm shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-900 dark:text-white" name="role" phx-change="update_role" phx-value-id={member.id}>
                  <%= for role <- @roles do %>
                    <option value={role} selected={role == member.role}><%= String.capitalize(role) %></option>
                  <% end %>
                </select>
                <button
                  type="button"
                  class="text-sm text-red-600 hover:text-red-500"
                  phx-click="remove_member"
                  phx-value-id={member.id}
                  data-confirm="Are you sure you want to remove this member?"
                >
                  Remove
                </button>
              <% else %>
                <span class="inline-flex items-center rounded-md bg-gray-100 dark:bg-slate-700 px-2 py-0.5 text-xs font-medium text-gray-600 dark:text-slate-200">
                  <%= String.capitalize(member.role) %>
                </span>
              <% end %>
            </div>
          </div>
        <% end %>
        <%= if Enum.empty?(@members) do %>
          <div class="px-6 py-8 text-center text-sm text-gray-500 dark:text-slate-400">No members yet.</div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :invitations, :list
  attr :invitation_form, :map
  attr :can_manage, :boolean
  attr :roles, :list

  defp invitations_section(assigns) do
    ~H"""
    <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <div class="lg:col-span-2 bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg">
        <div class="px-6 py-4 border-b border-gray-200 dark:border-slate-700 flex items-center justify-between">
          <div>
            <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Invitations</h2>
            <p class="text-sm text-gray-500 dark:text-slate-400">Pending invites expire 3 days after creation.</p>
          </div>
        </div>
        <div class="divide-y divide-gray-200 dark:divide-slate-700">
          <%= for invitation <- @invitations do %>
            <div class="px-6 py-4 flex items-center justify-between">
              <div>
                <div class="text-sm font-medium text-gray-900 dark:text-white"><%= invitation.email %></div>
                <div class="text-xs text-gray-500 dark:text-slate-400">
                  Role: <%= String.capitalize(invitation.role) %> • Status: <%= String.capitalize(invitation.status) %> • Expires <%= relative_time(invitation.expires_at) %>
                </div>
              </div>
              <%= if @can_manage and invitation.status == "pending" do %>
                <div class="flex items-center gap-3 text-sm">
                  <button class="text-teal-600 hover:text-teal-500" phx-click="resend_invitation" phx-value-id={invitation.id}>Resend</button>
                  <button class="text-red-600 hover:text-red-500" phx-click="cancel_invitation" phx-value-id={invitation.id}>Cancel</button>
                </div>
              <% end %>
            </div>
          <% end %>
          <%= if Enum.empty?(@invitations) do %>
            <div class="px-6 py-8 text-center text-sm text-gray-500 dark:text-slate-400">No pending invitations.</div>
          <% end %>
        </div>
      </div>
      <div class="bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg p-6">
        <h3 class="text-md font-semibold text-gray-900 dark:text-white mb-4">Invite a new member</h3>
        <%= if @can_manage do %>
          <.form for={@invitation_form} phx-submit="invite_member" class="space-y-4">
            <.form_field type="email" field={@invitation_form[:email]} label="Email" required={true} />
            <div>
              <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">Role</label>
              <select name="invitation[role]" class="mt-1 block w-full rounded-md border-gray-300 dark:border-slate-700 text-sm shadow-sm focus:border-teal-500 focus:ring-teal-500 dark:bg-slate-900 dark:text-white">
                <%= for role <- @roles do %>
                  <option value={role}><%= String.capitalize(role) %></option>
                <% end %>
              </select>
            </div>
            <.form_actions>
              <.primary_button phx-disable-with="Sending...">Send invitation</.primary_button>
            </.form_actions>
          </.form>
        <% else %>
          <p class="text-sm text-gray-500 dark:text-slate-400">Only administrators can send invitations.</p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :deployment_mode, :atom

  defp billing_section(assigns) do
    ~H"""
    <div class="bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg p-6">
      <h2 class="text-lg font-semibold text-gray-900 dark:text-white mb-2">Billing & Subscription</h2>
      <p class="text-sm text-gray-600 dark:text-slate-300">
        Subscription management is coming soon. You will be able to manage plan details and billing information here.
      </p>
      <%= if @deployment_mode == :self_hosted do %>
        <p class="mt-4 text-sm text-gray-500 dark:text-slate-400">
          In self-hosted installations, this section will surface license details and renewal options once available.
        </p>
      <% end %>
    </div>
    """
  end

  attr :organization_form, :map

  defp setup_section(assigns) do
    assigns = assign(assigns, :country_options, country_options())

    ~H"""
    <div class="max-w-xl mx-auto bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg p-6 mt-8">
      <h2 class="text-xl font-semibold text-gray-900 dark:text-white mb-2">Create your organization</h2>
      <p class="text-sm text-gray-600 dark:text-slate-300 mb-4">
        Get started by naming your organization. You will become the owner and can invite teammates afterwards.
      </p>
      <.form for={@organization_form} phx-submit="create_organization" class="space-y-4">
        <.form_field type="text" field={@organization_form[:name]} label="Organization name" required={true} />
        <.form_field type="select" field={@organization_form[:country]} label="Registration country" options={@country_options} prompt="Select country" />
        <.form_actions>
          <.primary_button phx-disable-with="Creating...">Create organization</.primary_button>
        </.form_actions>
      </.form>
    </div>
    """
  end

  defp tab_link_classes(active, align \\ :left)
  defp tab_link_classes(true, align) do
    align_class = if align == :right, do: "float-right", else: ""
    "group inline-flex items-center border-b-2 border-teal-500 text-teal-600 dark:text-teal-400 py-4 px-1 text-sm font-medium " <> align_class
  end

  defp tab_link_classes(false, align) do
    align_class = if align == :right, do: "float-right", else: ""
    base = "group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium"
    base <> " border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300 " <> align_class
  end

  defp tab_icon_classes(true) do
    "-ml-0.5 mr-2 h-5 w-5 text-teal-400 group-hover:text-teal-500"
  end

  defp tab_icon_classes(false) do
    "-ml-0.5 mr-2 h-5 w-5 text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300"
  end

  defp last_active_label(nil), do: "not yet"
  defp last_active_label(%DateTime{} = dt), do: relative_time(dt)

  defp relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(dt, now, :second)
    {direction, seconds} = if diff_seconds >= 0, do: {:future, diff_seconds}, else: {:past, -diff_seconds}

    {value, unit} =
      cond do
        seconds < 60 -> {seconds, "second"}
        seconds < 3600 -> {div(seconds, 60), "minute"}
        seconds < 86_400 -> {div(seconds, 3600), "hour"}
        seconds < 2_592_000 -> {div(seconds, 86_400), "day"}
        seconds < 31_536_000 -> {div(seconds, 2_592_000), "month"}
        true -> {div(seconds, 31_536_000), "year"}
      end

    unit = if value == 1, do: unit, else: unit <> "s"

    case direction do
      :future -> "in #{value} #{unit}"
      :past when seconds == 0 -> "just now"
      :past -> "#{value} #{unit} ago"
    end
  rescue
    _ -> Calendar.strftime(dt, "%b %d, %Y %H:%M %Z")
  end
end
