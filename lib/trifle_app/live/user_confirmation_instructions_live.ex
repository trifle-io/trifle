defmodule TrifleApp.UserConfirmationInstructionsLive do
  use TrifleApp, :live_view

  alias Trifle.Accounts

  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-start justify-center bg-gradient-to-br from-slate-50 to-slate-100 dark:from-slate-900 dark:to-slate-800 pt-16 pb-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div class="text-center">
          <div class="flex justify-center">
            <.trifle_logo class="h-20 w-20 text-teal-600 dark:text-teal-400" />
          </div>
          <h1 class="mt-6 text-3xl font-bold tracking-tight text-gray-900 dark:text-white">
            Resend confirmation email
          </h1>
          <p class="mt-2 text-sm text-gray-600 dark:text-gray-400">
            Enter your email and we'll send a fresh confirmation link
          </p>
        </div>

        <div class="bg-white dark:bg-slate-800 py-8 px-6 shadow-xl rounded-xl border border-gray-100 dark:border-slate-700">
          <.form_container
            for={@form}
            id="resend_confirmation_form"
            phx-submit="send_instructions"
            layout="simple"
          >
            <.form_field
              field={@form[:email]}
              type="email"
              label="Email address"
              required
              placeholder="Enter your email address"
            />
            <:actions>
              <.primary_button type="submit" phx-disable-with="Sending..." class="w-full">
                Resend confirmation instructions
              </.primary_button>
            </:actions>
          </.form_container>
        </div>

        <div class="text-center">
          <p class="text-sm text-gray-600 dark:text-gray-400">
            <%= if TrifleApp.RegistrationConfig.enabled?() do %>
              Don't have an account?
              <.link
                navigate={~p"/users/register"}
                class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
              >
                Sign up
              </.link>
              <span class="mx-2 text-gray-400 dark:text-slate-500">|</span>
            <% end %>
            <.link
              navigate={~p"/users/log_in"}
              class="font-medium text-teal-600 hover:text-teal-500 dark:text-teal-400 dark:hover:text-teal-300"
            >
              Back to sign in
            </.link>
          </p>
        </div>

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
    {:ok, assign(socket, form: to_form(%{}, as: "user"), page_title: "Resend Confirmation")}
  end

  def handle_event("send_instructions", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_confirmation_instructions(
        user,
        &url(~p"/users/confirm/#{&1}")
      )
    end

    info =
      "If your email is in our system and it has not been confirmed yet, you will receive an email with instructions shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> redirect(to: ~p"/")}
  end
end
