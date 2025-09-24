defmodule TrifleApp.OrganizationUsersLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.{Organization, OrganizationInvitation, OrganizationMembership}

  alias TrifleApp.OrganizationLive.Navigation

  def mount(_params, _session, socket) do
    current_user = socket.assigns[:current_user]
    membership = socket.assigns[:current_membership]

    socket =
      socket
      |> assign(:page_title, "Organization · Users")
      |> assign(:active_tab, :users)
      |> assign(:current_user, current_user)
      |> assign(:show_invite_modal, false)

    cond do
      is_nil(current_user) ->
        {:ok, socket}

      is_nil(membership) ->
        {:ok, push_navigate(socket, to: ~p"/organization")}

      true ->
        {:ok, load_users_state(socket, membership)}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <%= if @current_membership do %>
        <Navigation.nav active_tab={@active_tab} />

        <div class="bg-white dark:bg-slate-800 shadow-sm border border-gray-200 dark:border-slate-700 rounded-lg">
          <div class="px-6 py-4 border-b border-gray-200 dark:border-slate-700 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <h2 class="text-lg font-semibold text-gray-900 dark:text-white">Users & Invitations</h2>
              <p class="text-sm text-gray-500 dark:text-slate-400">
                Pending invitations appear at the top until they are accepted or cancelled.
              </p>
            </div>
            <%= if @can_manage do %>
              <.primary_button
                type="button"
                phx-click="open_invite_modal"
                class="gap-2"
                aria-label="Invite member"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-5 w-5"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5"
                  />
                </svg>
                <span class="hidden md:inline">Invite</span>
              </.primary_button>
            <% end %>
          </div>

          <div
            id="organization-users-list"
            class="divide-y divide-gray-200 dark:divide-slate-700"
            phx-hook="FastTooltip"
          >
            <%= if Enum.empty?(@pending_invitations) and Enum.empty?(@members) do %>
              <div class="px-6 py-8 text-center text-sm text-gray-500 dark:text-slate-400">
                No members or pending invitations yet.
              </div>
            <% else %>
              <%= for invitation <- @pending_invitations do %>
                <div class="px-6 py-4">
                  <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                    <div>
                      <div class="text-sm font-medium text-gray-900 dark:text-white">
                        {invitation.email}
                      </div>
                      <div class="text-xs text-gray-500 dark:text-slate-400">
                        Pending invitation • Expires {relative_time(invitation.expires_at)}
                      </div>
                    </div>
                    <div class="flex items-center justify-end gap-3">
                      <div class="flex items-center gap-2">
                        <%= if @can_manage do %>
                          <button
                            type="button"
                            class="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-gray-300 text-gray-600 shadow-sm transition hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-teal-500 focus:ring-offset-2 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-700 dark:focus:ring-offset-slate-800"
                            phx-click="resend_invitation"
                            phx-value-id={invitation.id}
                            data-tooltip="Resend invitation"
                            aria-label="Resend invitation"
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-4 w-4"
                              aria-hidden="true"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5"
                              />
                            </svg>
                            <span class="sr-only">Resend invitation</span>
                          </button>
                          <button
                            type="button"
                            class="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-red-200 text-red-600 shadow-sm transition hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:border-red-400 dark:text-red-300 dark:hover:bg-red-500/10 dark:focus:ring-offset-slate-800"
                            phx-click="cancel_invitation"
                            phx-value-id={invitation.id}
                            data-tooltip="Cancel invitation"
                            aria-label="Cancel invitation"
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-4 w-4"
                              aria-hidden="true"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
                              />
                            </svg>
                            <span class="sr-only">Cancel invitation</span>
                          </button>
                        <% end %>
                      </div>
                      <span class="inline-flex h-8 w-32 items-center justify-start rounded-md bg-gray-100 dark:bg-slate-700 px-3 text-sm font-medium text-gray-600 dark:text-slate-200">
                        {String.capitalize(invitation.role)}
                      </span>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= for member <- @members do %>
                <div class="px-6 py-4">
                  <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
                    <div>
                      <div class="text-sm font-medium text-gray-900 dark:text-white">
                        {member.user.email}
                        <%= if member.id == @current_membership.id do %>
                          <span class="ml-2 inline-flex items-center rounded-full bg-teal-100 px-2 py-0.5 text-xs font-medium text-teal-800">
                            You
                          </span>
                        <% end %>
                      </div>
                      <div class="text-xs text-gray-500 dark:text-slate-400">
                        Last active: {last_active_label(member.last_active_at)}
                      </div>
                    </div>
                    <div class="flex items-center justify-end gap-3">
                      <div class="flex items-center gap-2">
                        <%= if @can_manage and member.id != @current_membership.id do %>
                          <button
                            type="button"
                            class="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-red-200 text-red-600 shadow-sm transition hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:border-red-400 dark:text-red-300 dark:hover:bg-red-500/10 dark:focus:ring-offset-slate-800"
                            phx-click="remove_member"
                            phx-value-id={member.id}
                            data-confirm="Are you sure you want to remove this member?"
                            data-tooltip="Remove member"
                            aria-label="Remove member"
                          >
                            <svg
                              xmlns="http://www.w3.org/2000/svg"
                              fill="none"
                              viewBox="0 0 24 24"
                              stroke-width="1.5"
                              stroke="currentColor"
                              class="h-4 w-4"
                              aria-hidden="true"
                            >
                              <path
                                stroke-linecap="round"
                                stroke-linejoin="round"
                                d="M22 10.5h-6m-2.25-4.125a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0ZM4 19.235v-.11a6.375 6.375 0 0 1 12.75 0v.109A12.318 12.318 0 0 1 10.374 21c-2.331 0-4.512-.645-6.374-1.766Z"
                              />
                            </svg>
                            <span class="sr-only">Remove member</span>
                          </button>
                        <% end %>
                      </div>
                      <%= if @can_manage and member.id != @current_membership.id do %>
                        <form phx-change="update_role" phx-value-id={member.id}>
                          <div class="relative w-32">
                            <select
                              class="block w-full appearance-none rounded-md border border-gray-300 bg-white py-1.5 pl-3 pr-8 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-0 dark:border-slate-700 dark:bg-slate-900 dark:text-white"
                              name="role"
                            >
                              <%= for role <- @roles do %>
                                <option value={role} selected={role == member.role}>
                                  {String.capitalize(role)}
                                </option>
                              <% end %>
                            </select>
                            <div class="pointer-events-none absolute inset-y-0 right-3 flex items-center text-gray-400 dark:text-slate-400">
                              <svg
                                class="h-3.5 w-3.5"
                                xmlns="http://www.w3.org/2000/svg"
                                fill="none"
                                viewBox="0 0 20 20"
                                stroke="currentColor"
                                stroke-width="1.5"
                                aria-hidden="true"
                              >
                                <path stroke-linecap="round" stroke-linejoin="round" d="M6 8l4 4 4-4" />
                              </svg>
                            </div>
                          </div>
                        </form>
                      <% else %>
                        <span class="inline-flex h-8 w-32 items-center justify-start rounded-md bg-gray-100 dark:bg-slate-700 px-3 text-sm font-medium text-gray-600 dark:text-slate-200">
                          {String.capitalize(member.role)}
                        </span>
                      <% end %>
                    </div>
                  </div>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>

        <.app_modal
          id="invite-member"
          show={@show_invite_modal}
          on_cancel="close_invite_modal"
          size="md"
        >
          <:title>Invite a new member</:title>
          <:body>
            <%= if @can_manage do %>
              <.form for={@invitation_form} phx-submit="invite_member" class="space-y-4">
                <.form_field
                  type="email"
                  field={@invitation_form[:email]}
                  label="Email"
                  required={true}
                />
                <div>
                  <label class="block text-sm font-medium text-gray-700 dark:text-slate-300 mb-1">
                    Role
                  </label>
                  <div class="relative">
                    <select
                      name="invitation[role]"
                      class="mt-1 block w-full appearance-none rounded-md border border-gray-300 bg-white py-2 pl-3 pr-8 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-0 dark:border-slate-700 dark:bg-slate-900 dark:text-white"
                    >
                      <%= for role <- @roles do %>
                        <option value={role}>{String.capitalize(role)}</option>
                      <% end %>
                    </select>
                    <div class="pointer-events-none absolute inset-y-0 right-3 flex items-center text-gray-400">
                      <svg
                        class="h-4 w-4"
                        xmlns="http://www.w3.org/2000/svg"
                        fill="none"
                        viewBox="0 0 20 20"
                        stroke="currentColor"
                        stroke-width="1.5"
                      >
                        <path stroke-linecap="round" stroke-linejoin="round" d="M6 8l4 4 4-4" />
                      </svg>
                    </div>
                  </div>
                </div>
                <.form_actions>
                  <.primary_button phx-disable-with="Sending...">Send invitation</.primary_button>
                </.form_actions>
              </.form>
            <% else %>
              <p class="text-sm text-gray-500 dark:text-slate-400">
                Only administrators can send invitations.
              </p>
            <% end %>
          </:body>
        </.app_modal>
      <% else %>
        <div class="rounded-lg border border-dashed border-gray-300 dark:border-slate-600 bg-white dark:bg-slate-800 p-8 text-center text-sm text-gray-500 dark:text-slate-400">
          Create an organization first to manage users and invitations.
        </div>
      <% end %>
    </div>
    """
  end

  def handle_event("open_invite_modal", _params, %{assigns: %{can_manage: true}} = socket) do
    {:noreply, assign(socket, :show_invite_modal, true)}
  end

  def handle_event("open_invite_modal", _params, socket), do: {:noreply, socket}

  def handle_event("close_invite_modal", _params, socket) do
    socket =
      socket
      |> assign(:show_invite_modal, false)
      |> reset_invitation_form()

    {:noreply, socket}
  end

  def handle_event(
        "invite_member",
        %{"invitation" => invitation_params} = payload,
        %{
          assigns: %{
            organization: %Organization{} = organization,
            current_user: user,
            can_manage: true
          }
        } =
          socket
      ) do
    form_params = Map.get(payload, "organization_invitation", %{})

    params =
      form_params
      |> Map.merge(invitation_params)
      |> Map.put_new("role", "member")
      |> Map.update("email", nil, fn value ->
        if is_binary(value), do: String.trim(value), else: value
      end)

    case Organizations.create_invitation(organization, params, user) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> refresh_pending_invitations("Invitation sent. The link expires in 3 days.")
         |> assign(:show_invite_modal, false)
         |> reset_invitation_form()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :invitation_form, to_form(changeset))}
    end
  end

  def handle_event("invite_member", _params, socket), do: {:noreply, socket}

  def handle_event("resend_invitation", %{"id" => invitation_id}, socket) do
    with %OrganizationInvitation{} = invitation <-
           find_invitation(socket.assigns.pending_invitations, invitation_id),
         {:ok, _} <- Organizations.refresh_invitation(invitation) do
      {:noreply, refresh_pending_invitations(socket, "Invitation refreshed for another 3 days.")}
    else
      _ -> {:noreply, socket |> put_flash(:error, "Could not refresh invitation")}
    end
  end

  def handle_event("cancel_invitation", %{"id" => invitation_id}, socket) do
    with %OrganizationInvitation{} = invitation <-
           find_invitation(socket.assigns.pending_invitations, invitation_id),
         {:ok, _} <- Organizations.cancel_invitation(invitation) do
      {:noreply, refresh_pending_invitations(socket, "Invitation cancelled")}
    else
      _ -> {:noreply, socket |> put_flash(:error, "Could not cancel invitation")}
    end
  end

  def handle_event("update_role", %{"id" => member_id, "role" => role}, socket) do
    %{
      assigns: %{
        members: members,
        current_membership: current_membership,
        organization: organization
      }
    } =
      socket

    with true <- socket.assigns.can_manage,
         {:ok, %OrganizationMembership{} = target} <- fetch_membership(organization, member_id),
         false <- target.id == current_membership.id and role != target.role,
         :ok <- ensure_owner_count_allows_role_change(members, target, role) do
      case Organizations.update_membership_role(target, role) do
        {:ok, _membership} ->
          {:noreply, refresh_members(socket, "Role updated")}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, socket |> put_flash(:error, changeset_error_message(changeset))}
      end
    else
      false ->
        {:noreply, socket |> put_flash(:error, "You cannot change your own role this way")}

      {:error, :last_owner} ->
        {:noreply, socket |> put_flash(:error, "An organization must have at least one owner")}

      {:error, :wrong_organization} ->
        {:noreply,
         socket |> put_flash(:error, "Could not locate that member in this organization")}

      {:error, :not_found} ->
        {:noreply,
         socket |> put_flash(:error, "Could not find that member. Try refreshing the page.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_member", %{"id" => member_id}, socket) do
    %{
      assigns: %{
        members: members,
        current_membership: current_membership,
        organization: organization
      }
    } =
      socket

    with true <- socket.assigns.can_manage,
         {:ok, %OrganizationMembership{} = target} <- fetch_membership(organization, member_id),
         false <- target.id == current_membership.id,
         :ok <- ensure_owner_count_allows_removal(members, target) do
      case Organizations.remove_member(target) do
        {:ok, _} -> {:noreply, refresh_members(socket, "Member removed")}
        {:error, _} -> {:noreply, socket |> put_flash(:error, "Failed to remove member")}
      end
    else
      false ->
        {:noreply, socket |> put_flash(:error, "You cannot remove yourself")}

      {:error, :last_owner} ->
        {:noreply, socket |> put_flash(:error, "An organization must have at least one owner")}

      {:error, :wrong_organization} ->
        {:noreply,
         socket |> put_flash(:error, "Could not locate that member in this organization")}

      {:error, :not_found} ->
        {:noreply,
         socket |> put_flash(:error, "Could not find that member. Try refreshing the page.")}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_users_state(socket, %OrganizationMembership{} = membership) do
    organization =
      membership.organization || Organizations.get_organization!(membership.organization_id)

    socket
    |> assign(:current_membership, membership)
    |> assign(:organization, organization)
    |> assign(:can_manage, Organizations.membership_admin?(membership))
    |> assign(:roles, Organizations.membership_roles())
    |> assign(:members, Organizations.list_members(organization))
    |> assign(:pending_invitations, pending_invitations_for(organization))
    |> assign(:invitation_form, empty_invitation_form(organization))
    |> assign(:show_invite_modal, false)
  end

  defp refresh_members(socket, message) do
    members = Organizations.list_members(socket.assigns.organization)

    socket
    |> assign(:members, members)
    |> put_flash(:info, message)
  end

  defp refresh_pending_invitations(socket, message) do
    invitations = pending_invitations_for(socket.assigns.organization)

    socket
    |> assign(:pending_invitations, invitations)
    |> put_flash(:info, message)
  end

  defp pending_invitations_for(%Organization{} = organization) do
    organization
    |> Organizations.list_invitations()
    |> Enum.filter(&(&1.status == "pending"))
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  defp empty_invitation_form(%Organization{} = organization) do
    %OrganizationInvitation{organization_id: organization.id}
    |> OrganizationInvitation.changeset(%{})
    |> to_form()
  end

  defp reset_invitation_form(%{assigns: %{organization: %Organization{} = organization}} = socket) do
    assign(socket, :invitation_form, empty_invitation_form(organization))
  end

  defp reset_invitation_form(socket), do: socket

  defp find_invitation(invitations, id) do
    Enum.find(invitations, &id_matches?(&1.id, id))
  end

  defp fetch_membership(%Organization{} = organization, id) when is_binary(id) do
    case Organizations.get_membership(id) do
      %OrganizationMembership{} = membership ->
        if membership.organization_id == organization.id do
          {:ok, membership}
        else
          {:error, :wrong_organization}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp fetch_membership(_organization, _id), do: {:error, :not_found}

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

  defp last_active_label(nil), do: "not yet"
  defp last_active_label(%DateTime{} = dt), do: relative_time(dt)

  defp relative_time(%DateTime{} = dt) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(dt, now, :second)

    {direction, seconds} =
      if diff_seconds >= 0, do: {:future, diff_seconds}, else: {:past, -diff_seconds}

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

  defp id_matches?(struct_id, incoming_id) when is_binary(struct_id) do
    struct_id == incoming_id
  end

  defp id_matches?(struct_id, incoming_id) do
    to_string(struct_id) == incoming_id
  end
end
