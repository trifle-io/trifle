defmodule TrifleWeb.UserRegistrationLive do
  use TrifleWeb, :live_view

  alias Trifle.Accounts
  alias Trifle.Accounts.User

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-start justify-center bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-800 pt-16 pb-12 px-4 sm:px-6 lg:px-8">
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
            Create your account
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Get started with Trifle Analytics
          </p>
        </div>

        <!-- Registration Form -->
        <div class="bg-white dark:bg-slate-800 py-8 px-6 shadow-xl rounded-xl border border-gray-100 dark:border-slate-700">
          <.form_container 
            for={@form} 
            phx-submit="save" 
            phx-change="validate"
            phx-trigger-action={@trigger_submit}
            action={~p"/users/log_in?_action=registered"}
            method="post"
            layout="simple"
          >
            <.form_field 
              field={@form[:email]} 
              type="email" 
              label="Email address" 
              required 
              placeholder="Enter your email"
              help_text="We'll send you a confirmation email"
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
            <.link navigate={~p"/users/log_in"} class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300">
              Sign in
            </.link>
          </p>
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

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign_form(changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
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
    changeset = Accounts.change_user_registration(%User{}, user_params)
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
end
