defmodule TrifleWeb.UserLoginLive do
  use TrifleWeb, :live_view

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
            Welcome back
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Sign in to your account to continue
          </p>
        </div>
        
    <!-- Login Form -->
        <div class="bg-white dark:bg-slate-800 py-8 px-6 shadow-xl rounded-xl border border-gray-100 dark:border-slate-700">
          <.form_container for={@form} action={~p"/users/log_in"} phx-update="ignore" layout="simple">
            <.form_field
              field={@form[:email]}
              type="email"
              label="Email address"
              required
              placeholder="Enter your email"
            />

            <.form_field
              field={@form[:password]}
              type="password"
              label="Password"
              required
              placeholder="Enter your password"
            />

            <div class="flex items-center justify-between">
              <label class="flex items-center">
                <input
                  type="checkbox"
                  name={@form[:remember_me].name}
                  value="true"
                  class="h-4 w-4 rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-700 dark:focus:ring-teal-400"
                />
                <span class="ml-2 text-sm text-gray-900 dark:text-white">Remember me</span>
              </label>

              <.link
                navigate={~p"/users/reset_password"}
                class="text-sm font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
              >
                Forgot password?
              </.link>
            </div>

            <:actions>
              <.primary_button type="submit" phx-disable-with="Signing in..." class="w-full">
                Sign in
              </.primary_button>
            </:actions>
          </.form_container>
        </div>
        
    <!-- Navigation Links -->
        <%= if TrifleWeb.RegistrationConfig.enabled?() do %>
          <div class="text-center">
            <p class="text-sm text-gray-600 dark:text-gray-400">
              Don't have an account?
              <.link
                navigate={~p"/users/register"}
                class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
              >
                Sign up
              </.link>
            </p>
          </div>
        <% end %>
        
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
    email = live_flash(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
