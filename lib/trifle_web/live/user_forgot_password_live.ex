defmodule TrifleWeb.UserForgotPasswordLive do
  use TrifleWeb, :live_view

  alias Trifle.Accounts

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
            Forgot your password?
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Enter your email and we'll send you a password reset link
          </p>
        </div>
        
    <!-- Reset Form -->
        <div class="bg-white dark:bg-slate-800 py-8 px-6 shadow-xl rounded-xl border border-gray-100 dark:border-slate-700">
          <.form_container for={@form} phx-submit="send_email" layout="simple">
            <.form_field
              field={@form[:email]}
              type="email"
              label="Email address"
              required
              placeholder="Enter your email address"
            />

            <:actions>
              <.primary_button type="submit" phx-disable-with="Sending..." class="w-full">
                Send reset instructions
              </.primary_button>
            </:actions>
          </.form_container>
        </div>
        
    <!-- Navigation Links -->
        <div class="text-center">
          <.link
            navigate={~p"/users/log_in"}
            class="text-sm font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
          >
            ← Back to sign in
          </.link>
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

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Forgot Password")}
  end

  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/users/reset_password/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions to reset your password shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
