defmodule TrifleApp.UserLoginLive do
  use TrifleApp, :live_view

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-start justify-center bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-800 pt-16 pb-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <!-- Logo and Brand -->
        <div class="text-center">
          <div class="flex justify-center">
            <.trifle_logo class="h-20 w-20 text-teal-600 dark:text-teal-400" />
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
          <.form_container
            id="login_form"
            for={@form}
            action={~p"/users/log_in"}
            phx-update="ignore"
            layout="simple"
          >
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

          <div :if={@google_oauth_enabled} class="mt-6">
            <div class="relative">
              <div class="absolute inset-0 flex items-center" aria-hidden="true">
                <div class="w-full border-t border-gray-200 dark:border-slate-700"></div>
              </div>
              <div class="relative flex justify-center text-xs">
                <span class="px-2 bg-white dark:bg-slate-800 text-gray-500 dark:text-slate-400">
                  Or continue with
                </span>
              </div>
            </div>

            <div class="mt-4">
              <.link
                navigate={
                  if @invitation_token,
                    do: ~p"/auth/google?invitation_token=#{@invitation_token}",
                    else: ~p"/auth/google"
                }
                class="inline-flex w-full items-center justify-center gap-2 rounded-lg border border-gray-300 bg-white py-2 text-sm font-medium text-gray-700 transition hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800 dark:focus:ring-offset-slate-900"
              >
                <svg
                  class="h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  width="20"
                  height="24"
                  viewBox="0 0 40 48"
                  aria-hidden="true"
                >
                  <path
                    fill="#4285F4"
                    d="M39.2 24.45c0-1.55-.16-3.04-.43-4.45H20v8h10.73c-.45 2.53-1.86 4.68-4 6.11v5.05h6.5c3.78-3.48 5.97-8.62 5.97-14.71z"
                  />
                  <path
                    fill="#34A853"
                    d="M20 44c5.4 0 9.92-1.79 13.24-4.84l-6.5-5.05C24.95 35.3 22.67 36 20 36c-5.19 0-9.59-3.51-11.15-8.23h-6.7v5.2C5.43 39.51 12.18 44 20 44z"
                  />
                  <path
                    fill="#FABB05"
                    d="M8.85 27.77c-.4-1.19-.62-2.46-.62-3.77s.22-2.58.62-3.77v-5.2h-6.7C.78 17.73 0 20.77 0 24s.78 6.27 2.14 8.97l6.71-5.2z"
                  />
                  <path
                    fill="#E94235"
                    d="M20 12c2.93 0 5.55 1.01 7.62 2.98l5.76-5.76C29.92 5.98 25.39 4 20 4 12.18 4 5.43 8.49 2.14 15.03l6.7 5.2C10.41 15.51 14.81 12 20 12z"
                  />
                </svg>
                Sign in with Google
              </.link>
            </div>
          </div>
        </div>
        
    <!-- Navigation Links -->
        <%= if TrifleApp.RegistrationConfig.enabled?() or @invitation_token do %>
          <div class="text-center space-y-2">
            <p class="text-sm text-gray-600 dark:text-gray-400">
              <%= if @invitation_token && !TrifleApp.RegistrationConfig.enabled?() do %>
                You were invited to join.
              <% else %>
                Don't have an account?
              <% end %>
              <.link
                navigate={
                  if @invitation_token do
                    ~p"/users/register?invitation_token=#{@invitation_token}"
                  else
                    ~p"/users/register"
                  end
                }
                class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
              >
                Sign up
              </.link>
            </p>
            <p class="text-sm text-gray-600 dark:text-gray-400">
              <.link
                navigate={~p"/users/confirm"}
                class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
              >
                Resend confirmation instructions
              </.link>
            </p>
          </div>
        <% else %>
          <div class="text-center">
            <p class="text-sm text-gray-600 dark:text-gray-400">
              <.link
                navigate={~p"/users/confirm"}
                class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
              >
                Resend confirmation instructions
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

  def mount(params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    invitation_token = params["invitation_token"] |> normalize_token()

    socket =
      socket
      |> assign(form: form)
      |> assign(invitation_token: invitation_token)
      |> assign(:google_oauth_enabled, google_oauth_enabled?())
      |> assign(page_title: "Sign In")

    {:ok, socket, temporary_assigns: [form: form]}
  end

  defp normalize_token(nil), do: nil

  defp normalize_token(token) when is_binary(token) do
    cleaned = String.trim(token)
    if cleaned == "", do: nil, else: cleaned
  end

  defp normalize_token(_), do: nil

  defp google_oauth_enabled? do
    config = google_oauth_config()
    client_id = Map.get(config, :client_id) || Map.get(config, "client_id")
    client_secret = Map.get(config, :client_secret) || Map.get(config, "client_secret")
    !!(client_id && client_secret)
  end

  defp google_oauth_config do
    base = normalize_config(Application.get_env(:trifle, :google_oauth, %{}))

    env_overrides =
      %{
        client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID") || System.get_env("GOOGLE_CLIENT_ID"),
        client_secret:
          System.get_env("GOOGLE_OAUTH_CLIENT_SECRET") || System.get_env("GOOGLE_CLIENT_SECRET"),
        redirect_uri:
          System.get_env("GOOGLE_OAUTH_REDIRECT_URI") || System.get_env("GOOGLE_REDIRECT_URI")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or String.trim(v) == "" end)
      |> Map.new()

    Map.merge(base, env_overrides, fn _key, _base, override -> override end)
  end

  defp normalize_config(config) when is_map(config), do: config
  defp normalize_config(config) when is_list(config), do: Map.new(config)
  defp normalize_config(_), do: %{}
end
