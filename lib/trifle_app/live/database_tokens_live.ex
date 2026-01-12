defmodule TrifleApp.DatabaseTokensLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Database
  alias Trifle.Organizations.DatabaseToken

  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen dark:bg-slate-900">
      <.app_modal
        id="database-token-modal"
        show={@is_new}
        on_cancel={JS.patch(~p"/dbs/#{@database.id}/tokens")}
        size="md"
      >
        <:title>
          <%= if @token do %>
            Token created
          <% else %>
            Create a token
          <% end %>
        </:title>
        <:body>
          <%= if @token do %>
            <div class="space-y-6">
              <div class="rounded-md border border-amber-200 bg-amber-50 p-4 dark:border-amber-900/60 dark:bg-amber-500/10">
                <div class="flex gap-3">
                  <div class="flex-shrink-0">
                    <svg
                      class="h-5 w-5 text-amber-500 dark:text-amber-400"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                      aria-hidden="true"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </div>
                  <div>
                    <p class="text-sm text-amber-800 dark:text-amber-100">
                      Please copy your token now as this is the last time you can access it.
                    </p>
                  </div>
                </div>
              </div>

              <div class="space-y-3">
                <div class="min-w-0">
                  <p class="text-sm font-medium text-gray-900 dark:text-white">Token</p>
                  <code
                    id="database_token_token"
                    class="mt-1 block max-w-full break-all rounded-md bg-red-100 px-3 py-2 font-mono text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200"
                  >
                    {@token.token}
                  </code>
                </div>

                <button
                  type="button"
                  phx-click={
                    JS.dispatch("phx:copy", to: "#database_token_token")
                    |> JS.hide(to: "#database-token-copy-icon")
                    |> JS.show(to: "#database-token-copied-icon")
                    |> JS.hide(to: "#database-token-copy-label")
                    |> JS.show(to: "#database-token-copied-label")
                    |> JS.hide(
                      to: "#database-token-copied-icon",
                      transition: {"", "", ""},
                      time: 2000
                    )
                    |> JS.show(to: "#database-token-copy-icon", transition: {"", "", ""}, time: 2000)
                    |> JS.hide(
                      to: "#database-token-copied-label",
                      transition: {"", "", ""},
                      time: 2000
                    )
                    |> JS.show(to: "#database-token-copy-label", transition: {"", "", ""}, time: 2000)
                  }
                  class="inline-flex items-center gap-2 rounded-md border border-gray-200 bg-white px-3 py-2 text-sm font-medium text-gray-600 shadow-sm transition hover:border-gray-300 hover:text-gray-900 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:text-white"
                >
                  <svg
                    id="database-token-copy-icon"
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
                    id="database-token-copied-icon"
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

                  <span id="database-token-copy-label">Copy</span>
                  <span id="database-token-copied-label" class="hidden text-green-600">
                    Copied
                  </span>
                </button>
              </div>

              <div class="flex justify-end">
                <button
                  type="button"
                  phx-click="done"
                  class="inline-flex items-center rounded-md border border-gray-200 bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm hover:border-gray-300 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:bg-slate-700"
                >
                  Done
                </button>
              </div>
            </div>
          <% else %>
            <div class="space-y-6">
              <p class="text-sm text-gray-500 dark:text-slate-400">
                Tokens provide read-only API access for this database.
              </p>

              <div class="rounded-md border border-blue-200 bg-blue-50 p-4 text-sm text-blue-900 dark:border-blue-900/60 dark:bg-blue-500/10 dark:text-blue-100">
                Read access is always enabled. Write access is disabled for database tokens.
              </div>

              <.form for={@form} id="database-token-form" phx-submit="create" class="space-y-6">
                <div class="grid gap-6 sm:grid-cols-3 sm:items-start">
                  <div>
                    <label
                      for="database_token_name"
                      class="text-sm font-medium leading-6 text-gray-900 dark:text-white"
                    >
                      Name
                    </label>
                    <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                      A human-readable label so you know where the token is used.
                    </p>
                  </div>
                  <div class="sm:col-span-2">
                    <.input
                      field={@form[:name]}
                      autocomplete="off"
                      placeholder=""
                      class="block w-full rounded-md border border-gray-300 bg-white px-2.5 py-2 text-sm text-gray-900 shadow-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
                    />
                  </div>
                </div>

                <.form_actions>
                  <.secondary_button navigate={~p"/dbs/#{@database.id}/tokens"}>
                    Cancel
                  </.secondary_button>
                  <.primary_button phx-disable-with="Creating...">Create</.primary_button>
                </.form_actions>
              </.form>
            </div>
          <% end %>
        </:body>
      </.app_modal>

      <div class="space-y-6">
        <div class="sm:p-4">
          <div class="border-b border-gray-200 dark:border-slate-700">
            <nav class="-mb-px flex space-x-4 sm:space-x-8" aria-label="Database tabs">
              <.link
                navigate={~p"/dbs/#{@database.id}/transponders"}
                class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300"
              >
                <svg
                  class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25"
                  />
                </svg>
                <span class="hidden sm:block">Transponders</span>
              </.link>
              <.link
                navigate={~p"/dbs/#{@database.id}/tokens"}
                aria-current="page"
                class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-teal-500 text-teal-600 dark:text-teal-300"
              >
                <svg
                  class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z"
                  />
                </svg>
                <span class="hidden sm:block">Tokens</span>
              </.link>
              <.link
                navigate={~p"/dbs/#{@database.id}/settings"}
                class="group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium border-transparent text-gray-500 dark:text-slate-400 hover:border-gray-300 dark:hover:border-slate-500 hover:text-gray-700 dark:hover:text-slate-300"
              >
                <svg
                  class="text-gray-400 dark:text-slate-400 group-hover:text-gray-500 dark:group-hover:text-slate-300 -ml-0.5 mr-2 h-5 w-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z"
                  />
                </svg>
                <span class="hidden sm:block">Settings</span>
              </.link>
            </nav>
          </div>
        </div>

        <div class="space-y-6 px-4 pb-6 sm:px-6 lg:px-8">
          <div class="overflow-hidden rounded-lg bg-white shadow-sm dark:bg-slate-800">
            <div class="flex items-center justify-between border-b border-gray-100 px-4 py-3.5 text-sm font-semibold text-gray-900 sm:px-6 dark:border-slate-700 dark:text-white">
              <div class="flex items-center gap-2">
                <span>Tokens</span>
                <span class="inline-flex items-center rounded-md bg-teal-50 px-2 py-1 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-600/20 dark:bg-teal-900 dark:text-teal-200 dark:ring-teal-500/30">
                  {Enum.count(@tokens)}
                </span>
              </div>
              <.link
                navigate={~p"/dbs/#{@database.id}/tokens/new"}
                class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
              >
                <svg class="h-5 w-5 md:-ml-0.5 md:mr-1.5" viewBox="0 0 20 20" fill="currentColor">
                  <path d="M10.75 4.75a.75.75 0 00-1.5 0v4.5h-4.5a.75.75 0 000 1.5h4.5v4.5a.75.75 0 001.5 0v-4.5h4.5a.75.75 0 000-1.5h-4.5v-4.5z" />
                </svg>
                <span class="hidden md:inline">New Token</span>
              </.link>
            </div>

            <%= if Enum.empty?(@tokens) do %>
              <div class="px-6 py-12 text-center text-sm text-gray-500 dark:text-slate-400">
                <p class="text-base font-medium text-gray-900 dark:text-white">No tokens yet</p>
                <p class="mt-1">Create a token to authorize read-only API access.</p>
              </div>
            <% else %>
              <ul role="list" class="divide-y divide-gray-100 dark:divide-slate-700">
                <%= for token <- @tokens do %>
                  <li>
                    <div class="group flex flex-col gap-4 px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
                      <div class="min-w-0 flex-1">
                        <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                          <span class="text-sm font-medium text-gray-900 dark:text-white">
                            {token.name || "Token"}
                          </span>
                          <span class="text-xs text-gray-500 dark:text-slate-400">
                            ending
                            <span class="font-mono text-xs text-red-600 dark:text-red-300">
                              {String.slice(token.token, -5, 5)}
                            </span>
                          </span>
                        </div>

                        <p class="mt-2 flex flex-wrap items-center gap-2 text-xs text-gray-500 dark:text-slate-400">
                          <span>
                            Last used
                            <%= if token.updated_at do %>
                              <time datetime={
                                Calendar.strftime(token.updated_at, "%Y-%m-%dT%H:%M:%S")
                              }>
                                {Calendar.strftime(token.updated_at, "%b %d, %Y %I:%M %p")}
                              </time>
                            <% else %>
                              never
                            <% end %>
                          </span>
                          <span class="hidden sm:inline text-gray-300 dark:text-slate-600">•</span>
                          <span>
                            Expires
                            <%= if expires_at = token_expires_at(token) do %>
                              <time datetime={NaiveDateTime.to_iso8601(expires_at)}>
                                {Calendar.strftime(expires_at, "%b %d, %Y")}
                              </time>
                            <% else %>
                              unknown
                            <% end %>
                          </span>
                        </p>
                      </div>

                      <div class="flex items-center gap-3 sm:flex-none">
                        <span class="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20 dark:bg-green-500/10 dark:text-green-200 dark:ring-green-400/30">
                          Read-only
                        </span>
                        <button
                          type="button"
                          phx-click="delete"
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
    """
  end

  def mount(_params, _session, %{assigns: %{current_membership: nil}} = socket) do
    {:ok, redirect(socket, to: ~p"/organization/profile")}
  end

  def mount(%{"id" => id}, _session, %{assigns: %{current_membership: membership}} = socket) do
    if Organizations.membership_owner?(membership) do
      database = Organizations.get_database_for_org!(membership.organization_id, id)
      tokens = Organizations.list_databases_database_tokens(database)
      changeset = Organizations.change_database_token(%DatabaseToken{}, %{"database" => database})

      socket =
        socket
        |> assign(:database, database)
        |> assign(:tokens, tokens)
        |> assign(:token, nil)
        |> assign(:form, to_form(changeset))
        |> assign(:page_title, "Databases · #{database.display_name} · Tokens")
        |> assign(:nav_section, :databases)
        |> assign(:breadcrumb_links, database_breadcrumb_links(database, "Tokens"))

      {:ok, apply_action(socket, socket.assigns.live_action, %{"id" => id})}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only organization owners can manage database tokens.")
       |> push_navigate(to: ~p"/dbs")}
    end
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Databases · #{socket.assigns.database.display_name} · Tokens · New")
    |> assign(:is_new, true)
    |> assign(:token, nil)
    |> assign(
      :form,
      to_form(
        Organizations.change_database_token(
          %DatabaseToken{},
          %{"database" => socket.assigns.database}
        )
      )
    )
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Databases · #{socket.assigns.database.display_name} · Tokens")
    |> assign(:is_new, false)
    |> assign(:token, nil)
    |> assign(:tokens, Organizations.list_databases_database_tokens(socket.assigns.database))
  end

  defp apply_action(socket, _action, _params), do: socket

  def handle_event("create", %{"database_token" => params}, socket) do
    case Organizations.create_databases_database_token(params, socket.assigns.database) do
      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:ok, database_token} ->
        socket =
          socket
          |> assign(token: database_token)
          |> assign(
            :tokens,
            Organizations.list_databases_database_tokens(socket.assigns.database)
          )
          |> put_flash(:info, "Token created successfully.")

        {:noreply, socket}
    end
  end

  def handle_event("done", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/dbs/#{socket.assigns.database.id}/tokens")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    token = Organizations.get_database_token!(id)
    Organizations.delete_database_token(token)

    socket =
      socket
      |> assign(tokens: Organizations.list_databases_database_tokens(socket.assigns.database))
      |> put_flash(:info, "Token deleted successfully.")

    {:noreply, socket}
  end

  defp token_expires_at(%DatabaseToken{inserted_at: %NaiveDateTime{} = inserted_at}) do
    NaiveDateTime.add(inserted_at, 365 * 24 * 60 * 60, :second)
  end

  defp token_expires_at(_), do: nil

  defp database_breadcrumb_links(%Database{} = database, last) do
    name = database.display_name || "Database"

    [
      {"Databases", ~p"/dbs"},
      {name, ~p"/dbs/#{database.id}/transponders"},
      last
    ]
  end
end
