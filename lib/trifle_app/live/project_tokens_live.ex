defmodule TrifleApp.ProjectTokensLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.ProjectToken

  def render(assigns) do
    ~H"""
    <div class="flex flex-col min-h-screen dark:bg-slate-900">
      <.app_modal
        id="project-token-modal"
        show={@is_new}
        on_cancel={JS.patch(~p"/projects/#{@project.id}/tokens")}
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
                    id="project_token_token"
                    class="mt-1 block max-w-full break-all rounded-md bg-red-100 px-3 py-2 font-mono text-sm text-red-700 dark:bg-red-500/10 dark:text-red-200"
                  >
                    {@token.token}
                  </code>
                </div>

                <button
                  type="button"
                  phx-click={
                    JS.dispatch("phx:copy", to: "#project_token_token")
                    |> JS.hide(to: "#project-token-copy-icon")
                    |> JS.show(to: "#project-token-copied-icon")
                    |> JS.hide(to: "#project-token-copy-label")
                    |> JS.show(to: "#project-token-copied-label")
                    |> JS.hide(to: "#project-token-copied-icon", transition: {"", "", ""}, time: 2000)
                    |> JS.show(to: "#project-token-copy-icon", transition: {"", "", ""}, time: 2000)
                    |> JS.hide(
                      to: "#project-token-copied-label",
                      transition: {"", "", ""},
                      time: 2000
                    )
                    |> JS.show(to: "#project-token-copy-label", transition: {"", "", ""}, time: 2000)
                  }
                  class="inline-flex items-center gap-2 rounded-md border border-gray-200 bg-white px-3 py-2 text-sm font-medium text-gray-600 shadow-sm transition hover:border-gray-300 hover:text-gray-900 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-200 dark:hover:text-white"
                >
                  <svg
                    id="project-token-copy-icon"
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
                    id="project-token-copied-icon"
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

                  <span id="project-token-copy-label">Copy</span>
                  <span id="project-token-copied-label" class="hidden text-green-600">Copied</span>
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
                Tokens authenticate ingestion clients for this project. Configure the access level you need.
              </p>

              <.form for={@form} phx-submit="create" class="space-y-6">
                <div class="grid gap-6 sm:grid-cols-3 sm:items-start">
                  <div>
                    <label
                      for="project_token_name"
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

                <div class="grid gap-6 sm:grid-cols-3 sm:items-start">
                  <div>
                    <label
                      for="project_token_read"
                      class="text-sm font-medium leading-6 text-gray-900 dark:text-white"
                    >
                      Read access
                    </label>
                    <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                      Permit dashboards or Explore to fetch data with this token.
                    </p>
                  </div>
                  <div class="sm:col-span-2">
                    <div class="flex items-center gap-3">
                      <.input
                        field={@form[:read]}
                        type="checkbox"
                        class="h-5 w-5 rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-900"
                      />
                      <span class="text-sm text-gray-600 dark:text-slate-300">
                        Enable read operations
                      </span>
                    </div>
                  </div>
                </div>

                <div class="grid gap-6 sm:grid-cols-3 sm:items-start">
                  <div>
                    <label
                      for="project_token_write"
                      class="text-sm font-medium leading-6 text-gray-900 dark:text-white"
                    >
                      Write access
                    </label>
                    <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                      Allow this token to push metrics into the project.
                    </p>
                  </div>
                  <div class="sm:col-span-2">
                    <div class="flex items-center gap-3">
                      <.input
                        field={@form[:write]}
                        type="checkbox"
                        class="h-5 w-5 rounded border-gray-300 text-teal-600 focus:ring-teal-500 dark:border-slate-600 dark:bg-slate-900"
                      />
                      <span class="text-sm text-gray-600 dark:text-slate-300">
                        Enable write operations
                      </span>
                    </div>
                  </div>
                </div>

                <div class="flex items-center justify-end gap-3">
                  <.button
                    phx-disable-with="Creating..."
                    class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600"
                  >
                    Create
                  </.button>
                  <.link
                    navigate={~p"/projects/#{@project.id}/tokens"}
                    class="inline-flex items-center rounded-md border border-gray-200 bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm hover:border-gray-300 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:bg-slate-700"
                  >
                    Cancel
                  </.link>
                </div>
              </.form>
            </div>
          <% end %>
        </:body>
      </.app_modal>

      <div class="space-y-6">
        <div class="sm:p-4">
          <.project_nav project={@project} current={:tokens} />
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
                navigate={~p"/projects/#{@project.id}/tokens/new"}
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
                <p class="mt-1">Create a token to integrate your ingestion clients.</p>
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

                        <p class="mt-2 text-xs text-gray-500 dark:text-slate-400">
                          Last used
                          <%= if token.updated_at do %>
                            <time datetime={Calendar.strftime(token.updated_at, "%Y-%m-%dT%H:%M:%S")}>
                              {Calendar.strftime(token.updated_at, "%b %d, %Y %I:%M %p")}
                            </time>
                          <% else %>
                            never
                          <% end %>
                        </p>
                      </div>

                      <div class="flex items-center gap-3 sm:flex-none">
                        <span class={[
                          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium",
                          if(token.read,
                            do:
                              "bg-green-50 text-green-700 ring-1 ring-inset ring-green-600/20 dark:bg-green-500/10 dark:text-green-200 dark:ring-green-400/30",
                            else: "bg-gray-100 text-gray-500 dark:bg-slate-800 dark:text-slate-300"
                          )
                        ]}>
                          Read
                        </span>
                        <span class={[
                          "inline-flex items-center rounded-md px-2 py-1 text-xs font-medium",
                          if(token.write,
                            do:
                              "bg-green-50 text-green-700 ring-1 ring-inset ring-green-600/20 dark:bg-green-500/10 dark:text-green-200 dark:ring-green-400/30",
                            else: "bg-gray-100 text-gray-500 dark:bg-slate-800 dark:text-slate-300"
                          )
                        ]}>
                          Write
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

  def mount(params, _session, socket) do
    project = Organizations.get_project!(params["id"])
    tokens = Organizations.list_projects_project_tokens(project)
    changeset = Organizations.change_project_token(%ProjectToken{}, %{"project" => project})

    socket =
      socket
      |> assign(:project, project)
      |> assign(:tokens, tokens)
      |> assign(:token, nil)
      |> assign(:form, to_form(changeset))
      |> assign(:page_title, "Projects · #{project.name} · Tokens")
      |> assign(:breadcrumb_links, project_breadcrumb_links(project, "Tokens"))

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "Projects · #{socket.assigns.project.name} · Tokens · New")
    |> assign(:is_new, true)
    |> assign(:token, nil)
    |> assign(
      :form,
      to_form(
        Organizations.change_project_token(
          %ProjectToken{},
          %{"project" => socket.assigns.project}
        )
      )
    )
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Projects · #{socket.assigns.project.name} · Tokens")
    |> assign(:is_new, false)
    |> assign(:token, nil)
    |> assign(:tokens, Organizations.list_projects_project_tokens(socket.assigns.project))
  end

  defp apply_action(socket, _action, _params), do: socket

  def handle_event("create", %{"project_token" => project_token_params}, socket) do
    case Organizations.create_projects_project_token(project_token_params, socket.assigns.project) do
      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:ok, project_token} ->
        socket =
          socket
          |> assign(token: project_token)
          |> assign(:tokens, Organizations.list_projects_project_tokens(socket.assigns.project))
          |> put_flash(:info, "Token created successfully.")

        {:noreply, socket}
    end
  end

  def handle_event("done", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/projects/#{socket.assigns.project.id}/tokens")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    token = Organizations.get_project_token!(id)
    Organizations.delete_project_token(token)

    socket =
      socket
      |> assign(tokens: Organizations.list_projects_project_tokens(socket.assigns.project))
      |> put_flash(:info, "Token deleted successfully.")

    {:noreply, socket}
  end

  defp project_breadcrumb_links(project, last) do
    project_name = project.name || "Project"

    [
      {"Projects", ~p"/projects"},
      {project_name, ~p"/projects/#{project.id}/transponders"},
      last
    ]
  end
end
