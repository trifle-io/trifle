defmodule TrifleWeb.UserResetPasswordLive do
  use TrifleWeb, :live_view

  alias Trifle.Accounts

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-800 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Logo and Brand -->
        <div class="text-center">
          <div class="flex justify-center">
            <svg viewBox="0 0 1024 1024" class="h-20 w-20 text-teal-600 dark:text-teal-400" stroke="currentColor" fill="none" style="fill-rule:evenodd;clip-rule:evenodd;stroke-linecap:round;stroke-linejoin:round;stroke-miterlimit:1.5;">
              <path d="M512,255.985L767.995,768.015L256.005,768.015L512,255.985Z" stroke-width="48"/>
              <path d="M384.035,512L191.977,543.055" stroke-width="48" />
              <path d="M832.002,319.913L578.581,384.001" stroke-width="48" />
              <path d="M832.002,414.511L611.315,447.956" stroke-width="48" />
              <path d="M832.002,512L643.721,511.977" stroke-width="48" />
              <path d="M832.002,604.858L677.831,575.999" stroke-width="48" />
              <path d="M832.002,703.97L705.888,640.043" stroke-width="48" />
            </svg>
          </div>
          <h1 class="mt-6 text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
            Reset your password
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Enter your new password below
          </p>
        </div>

        <!-- Reset Form -->
        <div class="bg-white dark:bg-slate-800 py-8 px-6 shadow-xl rounded-xl border border-gray-100 dark:border-slate-700">
          <.form_container for={@form} phx-submit="reset_password" phx-change="validate" layout="simple">
            <.form_field 
              field={@form[:password]} 
              type="password" 
              label="New password" 
              required 
              placeholder="Enter your new password"
            />
            
            <.form_field 
              field={@form[:password_confirmation]} 
              type="password" 
              label="Confirm new password" 
              required 
              placeholder="Confirm your new password"
            />

            <:actions>
              <.primary_button type="submit" phx-disable-with="Resetting..." class="w-full">
                Reset password
              </.primary_button>
            </:actions>
          </.form_container>
        </div>

        <!-- Navigation Links -->
        <div class="text-center">
          <.link navigate={~p"/users/log_in"} class="text-sm font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300">
            ← Back to sign in
          </.link>
        </div>

        <!-- Footer -->
        <div class="text-center">
          <p class="text-xs text-gray-500 dark:text-gray-400">
            © <%= Date.utc_today().year %> Trifle Analytics. Secure analytics platform.
          </p>
        </div>
      </div>
    </div>
    """
  end

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  # Do not log in the user after reset password to avoid a
  # leaked token giving the user access to the account.
  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password reset successfully.")
         |> redirect(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, "Reset password link is invalid or it has expired.")
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, :form, to_form(source, as: "user"))
  end
end
