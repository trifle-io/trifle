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
            viewBox="0 0 118 96"
            class="h-20 w-20 text-teal-600 dark:text-teal-400"
            xmlns="http://www.w3.org/2000/svg"
            style="fill-rule:evenodd;clip-rule:evenodd;stroke-linejoin:round;stroke-miterlimit:2;"
            fill="currentColor"
            aria-hidden="true"
          >
            <g>
              <path d="M29.215,2.047C37.152,0.961 43.508,0.363 50.152,0.078C53.637,-0.074 67.691,0.012 70.957,0.203C76.324,0.516 84.574,1.434 89.316,2.242C96.105,3.402 101.809,4.902 105.629,6.535C107.598,7.375 110.719,8.953 111.613,9.562C112.5,10.164 113.902,11.625 114.52,12.594C115.727,14.484 116.449,16.426 116.887,18.949C118.324,27.23 117.898,36.5 115.539,48.316C114.211,54.957 111.848,61.074 108.152,67.441C106.855,69.672 106.406,70.34 104.484,72.914C99.918,79.012 95.602,83.098 89.59,87.004C83.141,91.191 77.805,93.363 70.277,94.855C63.547,96.188 58.363,96.336 50.965,95.406C43.156,94.422 38.105,92.715 30.629,88.527C26.566,86.254 24.082,84.438 20.461,81.098C14.148,75.273 9.59,68.715 5.992,60.289C4.074,55.789 2.281,49.395 1.246,43.371C-0.883,30.965 -0.234,18.473 2.805,13.305C3.582,11.984 5.387,10.219 6.941,9.258C9.711,7.547 13.355,5.949 17.18,4.766C21.012,3.582 25.66,2.531 29.215,2.047ZM27.879,8.539C34.543,7.316 41.863,6.66 53.34,6.25C55.539,6.172 65.457,6.297 68.516,6.438C75.973,6.789 83.957,7.559 89.047,8.418C97.645,9.875 104.043,11.859 107.445,14.133C108.578,14.891 110.062,16.445 110.418,17.242C110.793,18.094 111.438,21.348 111.688,23.652C111.891,25.531 112.004,32.246 111.836,32.414C111.719,32.535 110.496,32.094 107.613,30.898C104.812,29.738 102.59,28.992 99.715,28.246C98.609,27.961 97.836,27.676 97.418,27.398C97.07,27.168 95.84,26.062 94.68,24.941C88.258,18.738 86.594,17.555 84.305,17.555C82.383,17.555 80.59,18.562 77.262,21.516C76.438,22.246 75.441,23.004 75.047,23.199C73.898,23.77 73.656,23.641 70.973,21.035C67.727,17.883 66.707,17.281 64.594,17.281C63.332,17.281 62.184,17.652 61,18.438C60.328,18.883 56.02,22.574 51.914,26.223C49.156,28.672 48.333,30.138 47.356,30.169C46.755,30.188 45.48,28.598 43.582,26.688C39.137,22.227 35.836,19.387 34.882,19.106C33.725,18.766 32.512,19.046 31.427,19.651C30.078,20.402 29.496,21.07 18.715,31.805C12.324,38.168 7.074,43.312 7.047,43.238C6.785,42.461 6.25,37.945 6.031,34.629C5.832,31.656 5.945,25.309 6.238,22.906C6.727,18.891 7.117,17.324 7.926,16.168C10,13.199 16.949,10.543 27.879,8.539ZM58.348,28.191C61.207,25.562 62.883,24.129 63.637,23.672C63.898,23.512 64.238,23.383 64.394,23.383C65.059,23.379 65.984,24.23 70.789,29.254C71.91,30.426 72.504,30.938 73.023,31.18C74.703,31.961 75.305,31.633 79.223,27.789C82.305,24.766 83.012,24.137 83.777,23.746C84.184,23.535 84.223,23.543 84.793,23.906C85.5,24.359 86.988,25.715 90.945,29.512C94.312,32.746 94.492,32.855 97.789,33.801C101.449,34.852 104.758,35.988 107.324,37.074C108.73,37.672 110.246,38.266 110.691,38.395L111.5,38.629L111.414,39.383C111.367,39.797 111.227,40.527 111.098,41.004L110.863,41.875L105.469,41.926C100.441,41.973 97.871,41.891 93.18,41.535C90.051,41.297 83.891,41.227 80.984,41.391C76.395,41.656 72.984,42.164 69.125,43.164C63.062,44.734 60.102,46.289 52.188,52.051C48,55.102 46.016,56.371 43.512,57.602C39,59.82 35.363,60.672 31.316,60.461C29.047,60.344 27.539,60.09 24.367,59.305C21.676,58.637 18.367,57.941 16.613,57.676C15.113,57.445 12.238,57.129 11.656,57.125C11.469,57.125 11.344,57.129 11.234,57.086C10.977,56.98 10.836,56.59 10.289,55.16C9.723,53.695 8.366,48.602 8.262,48.534C8.193,48.489 16.182,40.784 20.358,36.71C24.275,32.89 31.644,24.698 33.355,24.603C34.799,24.523 39.888,30.32 40.747,31.229C41.411,31.932 45.809,36.942 47.544,37.075C48.788,37.171 53.266,32.765 53.266,32.765C55.359,30.952 56.074,30.285 58.348,28.191ZM69.617,49.004C72.449,48.184 76.281,47.512 79.629,47.242C81.973,47.055 90.461,47.176 93.992,47.449C96.258,47.625 98.691,47.691 103.445,47.695C107.66,47.703 109.848,47.754 109.848,47.844C109.848,48.098 108.918,51.359 108.535,52.449L108.156,53.535L106.801,53.629C106.055,53.684 104.07,53.824 102.395,53.941C95.98,54.398 89.785,55.395 83.375,57C80.641,57.684 78.559,58.281 72.988,59.969C65.073,62.367 61.473,63.207 56.66,63.77C53.336,64.156 46.957,64.055 44.734,63.574L43.922,63.402L44.531,63.148C47.125,62.074 48.422,61.297 53.949,57.484C60.594,52.898 61.098,52.578 63.426,51.434C65.777,50.281 67.414,49.641 69.617,49.004ZM76.242,64.649C86.039,61.691 91.516,60.539 100.023,59.645C101.664,59.469 103.691,59.32 104.531,59.312L106.059,59.293L105.633,60.141C105.094,61.207 103.746,63.559 102.996,64.731L102.422,65.625L100.477,65.723C96.27,65.926 92.734,66.469 88.031,67.629C81.422,69.262 75.43,71.336 66.211,75.184C59.824,77.848 56.672,78.961 52.68,79.961C44.613,81.977 37.801,81.816 28.836,79.398C26.871,78.867 26.477,78.711 25.828,78.227C24.156,76.969 20.289,72.828 18.082,69.93C16.723,68.148 13.766,63.41 13.766,63.02C13.766,62.598 19.43,63.609 24.812,64.992C26.527,65.434 29.574,66.219 31.59,66.734C38.32,68.465 41.875,69.035 47.762,69.324C54.059,69.633 61.062,68.875 67.297,67.203C69.344,66.652 74.102,65.297 76.242,64.649ZM65.641,81.301C81.859,74.492 89.555,72.109 97.922,71.309C98.184,71.281 98.449,71.254 98.516,71.242C98.902,71.168 96.328,74.133 94.105,76.312C90.141,80.207 85.914,83.094 80.891,85.34C76.703,87.215 71.102,88.793 66.598,89.371C59.957,90.223 53.328,89.953 46.633,88.559C44.773,88.172 40.469,86.965 40.871,86.945C43.988,86.781 46.184,86.609 47.844,86.398C53.352,85.691 59.117,84.039 65.641,81.301Z" />
            </g>
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
