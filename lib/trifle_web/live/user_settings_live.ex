defmodule TrifleWeb.UserSettingsLive do
  use TrifleWeb, :live_view

  alias Trifle.Accounts

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-4xl">
        <!-- Page Header -->
        <div class="pb-8">
          <h1 class="text-2xl font-bold leading-7 text-gray-900 dark:text-white">Account Settings</h1>
          <p class="mt-1 text-sm leading-6 text-gray-600 dark:text-gray-400">
            Manage your account email address and password settings
          </p>
        </div>

        <!-- Settings Sections -->
        <div class="divide-y divide-gray-900/10 dark:divide-slate-700">
          <!-- Email Settings Section -->
          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Email Address</h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Update your email address. You'll need to verify the new email before the change takes effect.
              </p>
            </div>

            <.form_container 
              for={@email_form} 
              phx-submit="update_email" 
              phx-change="validate_email" 
              layout="simple"
              class="bg-white dark:bg-slate-800 shadow-sm ring-1 ring-gray-900/5 dark:ring-slate-700 sm:rounded-xl md:col-span-2"
            >
              <div class="px-4 py-6 sm:p-8">
                <div class="grid max-w-2xl grid-cols-1 gap-x-6 gap-y-8">
                  <div class="col-span-full">
                    <.form_field 
                      field={@email_form[:email]} 
                      type="email" 
                      label="New email address" 
                      required 
                      placeholder="Enter your new email"
                    />
                  </div>

                  <div class="col-span-full">
                    <.form_field 
                      field={@email_form[:current_password]}
                      type="password" 
                      label="Current password" 
                      required 
                      placeholder="Enter your current password"
                      help_text="We need your current password to confirm this change"
                    />
                  </div>
                </div>
              </div>

              <:actions>
                <div class="flex items-center justify-end gap-x-6 border-t border-gray-900/10 dark:border-slate-700 px-4 py-4 sm:px-8">
                  <.primary_button phx-disable-with="Changing..." type="submit">
                    Update Email
                  </.primary_button>
                </div>
              </:actions>
            </.form_container>
          </div>

          <!-- Password Settings Section -->
          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Password</h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Update your password to keep your account secure. Use a strong password with at least 8 characters.
              </p>
            </div>

            <.form_container 
              for={@password_form} 
              phx-submit="update_password"
              phx-change="validate_password"
              action={~p"/users/log_in?_action=password_updated"}
              method="post"
              phx-trigger-action={@trigger_submit}
              layout="simple"
              class="bg-white dark:bg-slate-800 shadow-sm ring-1 ring-gray-900/5 dark:ring-slate-700 sm:rounded-xl md:col-span-2"
            >
              <div class="px-4 py-6 sm:p-8">
                <div class="grid max-w-2xl grid-cols-1 gap-x-6 gap-y-8">
                  <input type="hidden" name="user[email]" value={@current_email} />
                  
                  <div class="col-span-full">
                    <.form_field 
                      field={@password_form[:password]} 
                      type="password" 
                      label="New password" 
                      required 
                      placeholder="Enter your new password"
                      help_text="Must be at least 8 characters long"
                    />
                  </div>

                  <div class="col-span-full">
                    <.form_field 
                      field={@password_form[:password_confirmation]} 
                      type="password" 
                      label="Confirm new password" 
                      required 
                      placeholder="Confirm your new password"
                    />
                  </div>

                  <div class="col-span-full">
                    <.form_field 
                      field={@password_form[:current_password]}
                      type="password" 
                      label="Current password" 
                      required 
                      placeholder="Enter your current password"
                      help_text="We need your current password to confirm this change"
                    />
                  </div>
                </div>
              </div>

              <:actions>
                <div class="flex items-center justify-end gap-x-6 border-t border-gray-900/10 dark:border-slate-700 px-4 py-4 sm:px-8">
                  <.primary_button phx-disable-with="Changing..." type="submit">
                    Update Password
                  </.primary_button>
                </div>
              </:actions>
            </.form_container>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("update_email", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, password, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info) |> assign(email_form_current_password: nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form()

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset))}
    end
  end
end
