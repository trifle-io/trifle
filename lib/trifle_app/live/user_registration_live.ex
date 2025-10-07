defmodule TrifleApp.UserRegistrationLive do
  use TrifleApp, :live_view

  alias Trifle.Accounts
  alias Trifle.Accounts.User
  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationInvitation
  alias TrifleApp.RegistrationConfig

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-start justify-center bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-800 pt-16 pb-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Logo and Brand -->
        <div class="text-center">
          <div class="flex justify-center">
            <svg
              viewBox="0 0 1024 1024"
              class="h-20 w-20 text-teal-600 dark:text-teal-400"
              stroke="currentColor"
              fill="none"
              style="fill-rule:evenodd;clip-rule:evenodd;stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:1.5;"
            >
              <path d="M512,255.985L767.995,768.015L256.005,768.015L512,255.985Z" stroke-width="48" />
              <path d="M384.035,512L191.977,543.055" stroke-width="48" />
              <path d="M832.002,319.913L578.581,384.001" stroke-width="48" />
              <path d="M832.002,414.511L611.315,447.956" stroke-width="48" />
              <path d="M832.002,512L643.721,511.977" stroke-width="48" />
              <path d="M832.002,604.858L677.831,575.999" stroke-width="48" />
              <path d="M832.002,703.97L705.888,640.043" stroke-width="48" />
            </svg>
          </div>
          <h1 class="mt-6 text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
            {registration_title(@invitation)}
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            {registration_subtitle(@invitation)}
          </p>
        </div>
        
    <!-- Registration Form -->
        <div class="bg-white dark:bg-slate-800 py-8 px-6 shadow-xl rounded-xl border border-gray-100 dark:border-slate-700">
          <div
            :if={@invitation}
            class="mb-6 rounded-lg border border-teal-200 bg-teal-50 px-4 py-3 text-sm text-teal-900 dark:border-teal-700/70 dark:bg-slate-700/60 dark:text-teal-100"
          >
            <p class="font-medium">
              You're joining {invitation_org_name(@invitation)} as a {invitation_role_label(
                @invitation
              )}.
            </p>
            <p class="mt-1">
              We'll use the invitation email {@invitation.email} for your new account.
            </p>
          </div>

          <.form_container
            for={@form}
            phx-submit="save"
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            action={form_action(@invitation_token)}
            method="post"
            layout="simple"
          >
            <input
              :if={@invitation_token}
              type="hidden"
              name="invitation_token"
              value={@invitation_token}
            />

            <.form_field
              field={@form[:email]}
              type="email"
              label="Email address"
              required
              placeholder="Enter your email"
              help_text={email_help_text(@invitation)}
            />

            <.form_field
              field={@form[:password]}
              type="password"
              label="Password"
              required
              placeholder="Create a strong password"
              help_text="Must be at least 8 characters long"
            />

            <:actions>
              <.primary_button type="submit" phx-disable-with="Creating account..." class="w-full">
                Create account
              </.primary_button>
            </:actions>
          </.form_container>
        </div>
        
    <!-- Navigation Links -->
        <div class="text-center">
          <p class="text-sm text-gray-600 dark:text-gray-400">
            Already have an account?
            <.link
              navigate={~p"/users/log_in"}
              class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
            >
              Sign in
            </.link>
          </p>
        </div>
        
    <!-- Footer -->
        <div class="text-center">
          <p class="text-xs text-gray-500 dark:text-gray-400">
            © {Date.utc_today().year} Trifle Analytics. Secure analytics platform.
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(params, _session, socket) do
    case registration_context(params) do
      {:ok, %{mode: mode, invitation: invitation, token: token}} ->
        attrs = invitation_email_attrs(invitation)
        changeset = Accounts.change_user_registration(%User{}, attrs)

        socket =
          socket
          |> assign(
            trigger_submit: false,
            check_errors: false,
            invitation: invitation,
            invitation_token: token,
            registration_mode: mode,
            page_title: "Sign Up"
          )
          |> assign_form(changeset)

        {:ok, socket, temporary_assigns: [form: nil]}

      {:error, %{reason: reason, token: token}} ->
        {:ok,
         socket
         |> Phoenix.LiveView.put_flash(:error, registration_error_message(reason))
         |> redirect(to: login_path(token))}
    end
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    attrs = enforce_invitation_email(socket.assigns.invitation, user_params)

    case Accounts.register_user(attrs) do
      {:ok, user} ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &url(~p"/users/confirm/#{&1}")
          )

        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    attrs = enforce_invitation_email(socket.assigns.invitation, user_params)
    changeset = Accounts.change_user_registration(%User{}, attrs)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")

    if changeset.valid? do
      assign(socket, form: form, check_errors: false)
    else
      assign(socket, form: form)
    end
  end

  defp registration_context(params) do
    token = params["invitation_token"] |> normalize_token()

    cond do
      RegistrationConfig.enabled?() ->
        invitation =
          case token do
            nil ->
              nil

            _ ->
              case Organizations.get_active_invitation_by_token(token) do
                {:ok, invitation} -> invitation
                _ -> nil
              end
          end

        {:ok,
         %{
           mode: if(invitation, do: :open_with_invitation, else: :open),
           invitation: invitation,
           token: token
         }}

      token ->
        case Organizations.get_active_invitation_by_token(token) do
          {:ok, invitation} ->
            {:ok, %{mode: :invitation_only, invitation: invitation, token: token}}

          {:error, reason} ->
            {:error, %{reason: reason, token: token}}
        end

      true ->
        {:error, %{reason: :registration_disabled, token: nil}}
    end
  end

  defp registration_error_message(:registration_disabled),
    do:
      "Self-service registrations are currently disabled. Please use your invitation or contact an administrator."

  defp registration_error_message(:not_found),
    do: "We couldn't find that invitation. Please request a new invite."

  defp registration_error_message(:expired),
    do: "This invitation has expired. Please request a new invite."

  defp registration_error_message(:already_accepted),
    do: "This invitation was already accepted. Try signing in instead."

  defp registration_error_message(:cancelled),
    do: "This invitation has been cancelled. Please contact the organization admin."

  defp registration_error_message(_),
    do: "This invitation cannot be used. Please request a new invite."

  defp invitation_email_attrs(%OrganizationInvitation{email: email}) when is_binary(email) do
    %{"email" => email}
  end

  defp invitation_email_attrs(_), do: %{}

  defp enforce_invitation_email(%OrganizationInvitation{email: email}, params)
       when is_binary(email) do
    params
    |> Map.put("email", email)
  end

  defp enforce_invitation_email(_, params), do: params

  defp email_help_text(%OrganizationInvitation{email: email}) when is_binary(email) do
    "This invitation is for #{email}. We'll use this email for your account."
  end

  defp email_help_text(_invitation), do: "We'll send you a confirmation email"

  defp registration_title(nil), do: "Create your account"

  defp registration_title(invitation) do
    "Join #{invitation_org_name(invitation)}"
  end

  defp registration_subtitle(%OrganizationInvitation{} = invitation) do
    "Complete your account setup to access #{invitation_org_name(invitation)} on Trifle."
  end

  defp registration_subtitle(_), do: "Get started with Trifle Analytics"

  defp invitation_org_name(%OrganizationInvitation{organization: %{name: name}})
       when is_binary(name) do
    name
  end

  defp invitation_org_name(%OrganizationInvitation{}), do: "this organization"
  defp invitation_org_name(_), do: "Trifle"

  defp invitation_role_label(%OrganizationInvitation{role: role}) when is_binary(role) do
    role
    |> String.downcase()
    |> String.capitalize()
  end

  defp invitation_role_label(_), do: "Member"

  defp form_action(nil), do: ~p"/users/log_in?_action=registered"
  defp form_action(token), do: ~p"/users/log_in?_action=registered&invitation_token=#{token}"

  defp login_path(nil), do: ~p"/users/log_in"
  defp login_path(token), do: ~p"/users/log_in?invitation_token=#{token}"

  defp normalize_token(nil), do: nil

  defp normalize_token(token) when is_binary(token) do
    trimmed = String.trim(token)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_token(_), do: nil
end
