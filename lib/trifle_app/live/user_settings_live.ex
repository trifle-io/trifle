defmodule TrifleApp.UserSettingsLive do
  use TrifleApp, :live_view

  alias Trifle.Accounts
  alias Trifle.Accounts.UserApiToken

  def render(assigns) do
    ~H"""
    <div class="px-4 sm:px-6 lg:px-8">
      <.app_modal
        id="user-token-modal"
        show={@show_user_token_modal}
        on_cancel={JS.push("close_user_token_modal")}
        size="md"
      >
        <:title>
          <%= if @issued_user_token do %>
            Token created
          <% else %>
            Create a token
          <% end %>
        </:title>
        <:body>
          <%= if @issued_user_token do %>
            <div class="space-y-6">
              <div class="rounded-md border border-amber-200 bg-amber-50 p-4 dark:border-amber-900/60 dark:bg-amber-500/10">
                <p class="text-sm text-amber-800 dark:text-amber-100">
                  Please copy your token now as this is the last time you can access it.
                </p>
              </div>

              <div class="space-y-3">
                <div class="min-w-0">
                  <p class="text-sm font-medium text-gray-900 dark:text-white">Token</p>
                  <code
                    id="user_token_token"
                    class="mt-1 block max-w-full break-all rounded-md bg-red-100 px-3 py-2 font-mono text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200"
                  >
                    {@issued_user_token.token}
                  </code>
                </div>

                <button
                  type="button"
                  phx-click={
                    JS.dispatch("phx:copy", to: "#user_token_token")
                    |> JS.hide(to: "#user-token-copy-icon")
                    |> JS.show(to: "#user-token-copied-icon")
                    |> JS.hide(to: "#user-token-copy-label")
                    |> JS.show(to: "#user-token-copied-label")
                    |> JS.hide(to: "#user-token-copied-icon", transition: {"", "", ""}, time: 2000)
                    |> JS.show(to: "#user-token-copy-icon", transition: {"", "", ""}, time: 2000)
                    |> JS.hide(to: "#user-token-copied-label", transition: {"", "", ""}, time: 2000)
                    |> JS.show(to: "#user-token-copy-label", transition: {"", "", ""}, time: 2000)
                  }
                  class="inline-flex items-center gap-2 rounded-md border border-gray-200 bg-white px-3 py-2 text-sm font-medium text-gray-600 shadow-sm transition hover:border-gray-300 hover:text-gray-900 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:text-white"
                >
                  <svg
                    id="user-token-copy-icon"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="h-5 w-5"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 002.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 00-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 00.75-.75 2.25 2.25 0 00-.1-.664m-5.8 0A2.251 2.251 0 0113.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25zM6.75 12h.008v.008H6.75V12zm0 3h.008v.008H6.75V15zm0 3h.008v.008H6.75V18z"
                    />
                  </svg>

                  <svg
                    id="user-token-copied-icon"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    class="hidden h-5 w-5 text-green-600"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>

                  <span id="user-token-copy-label">Copy</span>
                  <span id="user-token-copied-label" class="hidden text-green-600">Copied</span>
                </button>
              </div>

              <div class="flex justify-end">
                <button
                  type="button"
                  phx-click="done_user_token"
                  class="inline-flex items-center rounded-md border border-gray-200 bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm hover:border-gray-300 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:bg-slate-700"
                >
                  Done
                </button>
              </div>
            </div>
          <% else %>
            <div class="space-y-6">
              <p class="text-sm text-gray-500 dark:text-slate-400">
                Tokens let tools and API clients authenticate as your user account.
              </p>

              <%= if @user_token_error do %>
                <div class="rounded-md border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-800 dark:bg-red-500/10 dark:text-red-200">
                  {@user_token_error}
                </div>
              <% end %>

              <form id="user-token-form" phx-submit="create_user_token" class="space-y-6">
                <div class="grid gap-6 sm:grid-cols-3 sm:items-start">
                  <div>
                    <label
                      for="user_token_name"
                      class="text-sm font-medium leading-6 text-gray-900 dark:text-white"
                    >
                      Name
                    </label>
                    <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                      A label so you can identify where this token is used.
                    </p>
                  </div>
                  <div class="sm:col-span-2">
                    <input
                      id="user_token_name"
                      name="user_token[name]"
                      value={@new_user_token_name}
                      autocomplete="off"
                      class="block w-full rounded-md border border-gray-300 bg-white px-2.5 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
                    />
                  </div>
                </div>

                <.form_actions>
                  <button
                    type="button"
                    phx-click="close_user_token_modal"
                    class="inline-flex items-center rounded-md border border-gray-300 bg-white px-3 py-2 text-sm font-semibold text-gray-700 shadow-sm hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
                  >
                    Cancel
                  </button>
                  <.primary_button phx-disable-with="Creating...">Create</.primary_button>
                </.form_actions>
              </form>
            </div>
          <% end %>
        </:body>
      </.app_modal>

      <div class="mx-auto max-w-4xl">
        <div class="pb-8">
          <h1 class="text-2xl font-bold leading-7 text-gray-900 dark:text-white">Account Settings</h1>
          <p class="mt-1 text-sm leading-6 text-gray-600 dark:text-gray-400">
            Manage your profile, theme, email address, password settings, and API tokens.
          </p>
        </div>

        <div class="divide-y divide-gray-900/10 dark:divide-slate-700">
          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
                Profile
              </h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Set your display name. This is shown in greetings and activity trails.
              </p>
            </div>

            <.form_container
              for={@profile_form}
              phx-submit="update_profile"
              phx-change="validate_profile"
              layout="simple"
              class="bg-white dark:bg-slate-800 shadow-sm ring-1 ring-gray-900/5 dark:ring-slate-700 sm:rounded-xl md:col-span-2"
            >
              <div class="px-4 py-6 sm:p-8">
                <div class="grid max-w-2xl grid-cols-1 gap-x-6 gap-y-8">
                  <div class="col-span-full">
                    <.form_field
                      field={@profile_form[:name]}
                      type="text"
                      label="Name"
                      placeholder="Your name"
                      maxlength={160}
                    />
                  </div>
                </div>
              </div>

              <:actions>
                <div class="flex items-center justify-end gap-x-6 border-t border-gray-900/10 dark:border-slate-700 px-4 py-4 sm:px-8">
                  <.primary_button phx-disable-with="Saving..." type="submit">
                    Save Profile
                  </.primary_button>
                </div>
              </:actions>
            </.form_container>
          </div>

          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">
                Theme Preference
              </h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Choose your preferred theme. System will automatically switch between light and dark based on your device settings.
              </p>
            </div>

            <.form_container
              for={@theme_form}
              phx-submit="update_theme"
              phx-change="validate_theme"
              layout="simple"
              class="bg-white dark:bg-slate-800 shadow-sm ring-1 ring-gray-900/5 dark:ring-slate-700 sm:rounded-xl md:col-span-2"
            >
              <div class="px-4 py-6 sm:p-8">
                <div class="grid max-w-2xl grid-cols-1 gap-x-6 gap-y-8">
                  <div class="col-span-full">
                    <.form_field
                      field={@theme_form[:theme]}
                      type="select"
                      label="Theme"
                      options={[
                        {"Light", "light"},
                        {"Dark", "dark"},
                        {"System", "system"}
                      ]}
                      help_text="System theme follows your device's appearance settings"
                    />
                  </div>
                </div>
              </div>

              <:actions>
                <div class="flex items-center justify-end gap-x-6 border-t border-gray-900/10 dark:border-slate-700 px-4 py-4 sm:px-8">
                  <.primary_button phx-disable-with="Saving..." type="submit">
                    Save Theme
                  </.primary_button>
                </div>
              </:actions>
            </.form_container>
          </div>

          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Email Address</h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Update your email address. You'll need to verify the new email before the change takes effect.
              </p>
            </div>

            <.form_container
              id="email_form"
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
                      id="email_current_password"
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

          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">Password</h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Update your password to keep your account secure. Use a strong password with at least 8 characters.
              </p>
            </div>

            <.form_container
              id="password_form"
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
                      id="password_current_password"
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

          <div class="grid grid-cols-1 gap-x-8 gap-y-8 py-10 md:grid-cols-3">
            <div class="px-4 sm:px-0">
              <h2 class="text-base/7 font-semibold text-gray-900 dark:text-white">API Tokens</h2>
              <p class="mt-1 text-sm/6 text-gray-600 dark:text-gray-400">
                Manage user API tokens used by CLI and API clients.
              </p>
            </div>

            <div class="md:col-span-2">
              <div class="overflow-hidden rounded-lg bg-white shadow-sm dark:bg-slate-800">
                <div class="flex items-center justify-between border-b border-gray-100 px-4 py-3.5 text-sm font-semibold text-gray-900 sm:px-6 dark:border-slate-700 dark:text-white">
                  <div class="flex items-center gap-2">
                    <span>Tokens</span>
                    <span class="inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/20 dark:bg-teal-900 dark:text-teal-200 dark:ring-teal-500/30">
                      {Enum.count(@user_tokens)}
                    </span>
                  </div>
                  <button
                    type="button"
                    phx-click="open_user_token_modal"
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
                  >
                    <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                      <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
                    </svg>
                    <span class="hidden md:inline">New Token</span>
                  </button>
                </div>

                <%= if Enum.empty?(@user_tokens) do %>
                  <div class="px-6 py-12 text-center text-sm text-gray-500 dark:text-slate-400">
                    <p class="text-base font-medium text-gray-900 dark:text-white">No tokens yet</p>
                    <p class="mt-1">Create a token to authenticate CLI or API access.</p>
                  </div>
                <% else %>
                  <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-700">
                    <%= for token <- @user_tokens do %>
                      <li>
                        <div class="group flex flex-col gap-4 px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
                          <div class="min-w-0 flex-1">
                            <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                              <span class="text-sm font-medium text-gray-900 dark:text-white">
                                {token.name || "Token"}
                              </span>
                              <span class="text-xs text-gray-500 dark:text-slate-400">
                                id ending
                                <span class="font-mono text-xs text-red-600 dark:text-red-300">
                                  {String.slice(token.id, -6, 6)}
                                </span>
                              </span>
                            </div>

                            <p class="mt-2 flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-slate-400">
                              <span>
                                Last used
                                <%= if token.last_used_at do %>
                                  <time datetime={DateTime.to_iso8601(token.last_used_at)}>
                                    {format_datetime(token.last_used_at)}
                                  </time>
                                <% else %>
                                  never
                                <% end %>
                              </span>
                              <span class="hidden sm:inline text-gray-300 dark:text-slate-600">
                                •
                              </span>
                              <span>
                                Created
                                <time datetime={NaiveDateTime.to_iso8601(token.inserted_at)}>
                                  {format_datetime(token.inserted_at)}
                                </time>
                              </span>
                              <span class="hidden sm:inline text-gray-300 dark:text-slate-600">
                                •
                              </span>
                              <span>
                                Expires
                                <%= if expires_at = token_expires_at(token) do %>
                                  <time datetime={DateTime.to_iso8601(expires_at)}>
                                    {format_date(expires_at)}
                                  </time>
                                <% else %>
                                  never
                                <% end %>
                              </span>
                            </p>

                            <p class="mt-1 flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-slate-400">
                              <span>Created by {token.created_by || "unknown"}</span>
                              <span class="hidden sm:inline text-gray-300 dark:text-slate-600">
                                •
                              </span>
                              <span>Created from {token.created_from || "unknown"}</span>
                              <span class="hidden sm:inline text-gray-300 dark:text-slate-600">
                                •
                              </span>
                              <span>Last used from {token.last_used_from || "unknown"}</span>
                            </p>
                          </div>

                          <div class="flex items-center gap-3 sm:flex-none">
                            <button
                              type="button"
                              phx-click="delete_user_token"
                              phx-value-id={token.id}
                              data-confirm="Are you sure?"
                              title="Delete token"
                              class="inline-flex items-center justify-center rounded-md border border-gray-300 bg-white p-2 text-gray-500 transition hover:border-red-400 hover:text-red-600 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300 dark:hover:border-red-400 dark:hover:text-red-300"
                            >
                              <svg
                                xmlns="http://www.w3.org/2000/svg"
                                fill="none"
                                viewBox="0 0 24 24"
                                stroke-width="1.5"
                                stroke="currentColor"
                                class="h-5 w-5"
                              >
                                <path
                                  stroke-linecap="round"
                                  stroke-linejoin="round"
                                  d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0"
                                />
                              </svg>
                            </button>
                          </div>
                        </div>
                      </li>
                    <% end %>
                  </ul>
                <% end %>
              </div>
            </div>
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

    {:ok, push_navigate(socket, to: ~p"/users/settings"), layout: {TrifleApp.Layouts, :app}}
  end

  def mount(_params, _session, socket) do
    user = Accounts.get_user!(socket.assigns.current_user.id)
    email_changeset = Accounts.change_user_email(user)
    password_changeset = Accounts.change_user_password(user)
    theme_changeset = Accounts.change_user_theme(user)
    profile_changeset = Accounts.change_user_profile(user)
    user_tokens = Accounts.list_user_api_tokens(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:email_form_current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:theme_form, to_form(theme_changeset))
      |> assign(:profile_form, to_form(profile_changeset))
      |> assign(:user_tokens, user_tokens)
      |> assign(:show_user_token_modal, false)
      |> assign(:issued_user_token, nil)
      |> assign(:new_user_token_name, "CLI token")
      |> assign(:user_token_error, nil)
      |> assign(:trigger_submit, false)
      |> assign(:page_title, "Account Settings")

    {:ok, socket, layout: {TrifleApp.Layouts, :app}}
  end

  def handle_event("validate_email", params, socket) do
    user_params = Map.get(params, "user", %{})
    password = Map.get(params, "current_password", Map.get(user_params, "current_password", ""))

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form, email_form_current_password: password)}
  end

  def handle_event("validate_profile", %{"user" => user_params}, socket) do
    profile_form =
      socket.assigns.current_user
      |> Accounts.change_user_profile(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, profile_form: profile_form)}
  end

  def handle_event("update_profile", %{"user" => user_params}, socket) do
    user = Accounts.get_user!(socket.assigns.current_user.id)

    case Accounts.update_user_profile(user, user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(profile_form: to_form(Accounts.change_user_profile(user)))
         |> assign(current_user: user)
         |> put_flash(:info, "Profile updated successfully.")}

      {:error, changeset} ->
        {:noreply, assign(socket, profile_form: to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("update_email", params, socket) do
    user_params = Map.get(params, "user", %{})
    password = Map.get(params, "current_password", Map.get(user_params, "current_password", ""))
    user = Accounts.get_user!(socket.assigns.current_user.id)

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
    user_params = Map.get(params, "user", %{})
    password = Map.get(params, "current_password", Map.get(user_params, "current_password", ""))

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    user_params = Map.get(params, "user", %{})
    password = Map.get(params, "current_password", Map.get(user_params, "current_password", ""))
    user_params = Map.delete(user_params, "current_password")
    user = Accounts.get_user!(socket.assigns.current_user.id)

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

  def handle_event("open_user_token_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_user_token_modal, true)
     |> assign(:issued_user_token, nil)
     |> assign(:user_token_error, nil)}
  end

  def handle_event("close_user_token_modal", _params, socket) do
    {:noreply, close_user_token_modal(socket)}
  end

  def handle_event("done_user_token", _params, socket) do
    {:noreply, close_user_token_modal(socket)}
  end

  def handle_event("create_user_token", %{"user_token" => params}, socket) do
    user = Accounts.get_user!(socket.assigns.current_user.id)
    name = params |> Map.get("name") |> normalize_name()

    case Accounts.create_user_api_token(user, user_token_create_attrs(socket, name)) do
      {:ok, _record, token} ->
        {:noreply,
         socket
         |> assign(:issued_user_token, %{token: token})
         |> assign(:new_user_token_name, name || "CLI token")
         |> assign(:user_token_error, nil)
         |> refresh_user_tokens(user)
         |> put_flash(:info, "Token created successfully.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:show_user_token_modal, true)
         |> assign(:issued_user_token, nil)
         |> assign(:new_user_token_name, name || socket.assigns.new_user_token_name)
         |> assign(:user_token_error, format_changeset_errors(changeset))}
    end
  end

  def handle_event("delete_user_token", %{"id" => token_id}, socket) do
    user = Accounts.get_user!(socket.assigns.current_user.id)

    case Accounts.delete_user_api_token(user, token_id) do
      {:ok, _token} ->
        {:noreply,
         socket
         |> refresh_user_tokens(user)
         |> put_flash(:info, "Token deleted successfully.")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Token was not found.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Token could not be deleted.")}
    end
  end

  def handle_event("validate_theme", params, socket) do
    %{"user" => user_params} = params

    theme_form =
      socket.assigns.current_user
      |> Accounts.change_user_theme(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, theme_form: theme_form)}
  end

  def handle_event("update_theme", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_theme(user, user_params) do
      {:ok, updated_user} ->
        theme_form =
          updated_user
          |> Accounts.change_user_theme()
          |> to_form()

        {:noreply,
         socket
         |> assign(theme_form: theme_form)
         |> assign(current_user: updated_user)
         |> put_flash(:info, "Theme preference updated successfully.")
         |> push_event("theme-changed", %{theme: updated_user.theme})}

      {:error, changeset} ->
        {:noreply, assign(socket, theme_form: to_form(changeset))}
    end
  end

  defp close_user_token_modal(socket) do
    socket
    |> assign(:show_user_token_modal, false)
    |> assign(:issued_user_token, nil)
    |> assign(:user_token_error, nil)
  end

  defp refresh_user_tokens(socket, user) do
    assign(socket, :user_tokens, Accounts.list_user_api_tokens(user))
  end

  defp user_token_create_attrs(socket, name) do
    %{
      name: name || "CLI token",
      created_by: "web-ui",
      created_from: socket_host(socket)
    }
  end

  defp socket_host(socket) do
    case Map.get(socket, :host_uri) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end

  defp normalize_name(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_name(_), do: nil

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {_field, errors} -> errors end)
    |> Enum.join(", ")
  end

  defp token_expires_at(%UserApiToken{expires_at: %DateTime{} = expires_at}), do: expires_at
  defp token_expires_at(_), do: nil

  defp format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp format_datetime(%NaiveDateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y %I:%M %p")
  end

  defp format_date(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end
end
