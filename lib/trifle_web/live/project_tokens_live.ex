defmodule TrifleWeb.ProjectTokensLive do
  use TrifleWeb, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.ProjectToken

  def render(assigns) do
    ~H"""
    <div>
      <div class="sm:p-4">
        <div class="border-b border-gray-200">
          <nav class="-mb-px space-x-8" aria-label="Tabs">
            <.link navigate={~p"/app/projects/#{@project.id}"} class="border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium">
              <svg class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3.375 19.5h17.25m-17.25 0a1.125 1.125 0 01-1.125-1.125M3.375 19.5h7.5c.621 0 1.125-.504 1.125-1.125m-9.75 0V5.625m0 12.75v-1.5c0-.621.504-1.125 1.125-1.125m18.375 2.625V5.625m0 12.75c0 .621-.504 1.125-1.125 1.125m1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125m0 3.75h-7.5A1.125 1.125 0 0112 18.375m9.75-12.75c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125m19.5 0v1.5c0 .621-.504 1.125-1.125 1.125M2.25 5.625v1.5c0 .621.504 1.125 1.125 1.125m0 0h17.25m-17.25 0h7.5c.621 0 1.125.504 1.125 1.125M3.375 8.25c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125m17.25-3.75h-7.5c-.621 0-1.125.504-1.125 1.125m8.625-1.125c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125M12 10.875v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 10.875c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125M13.125 12h7.5m-7.5 0c-.621 0-1.125.504-1.125 1.125M20.625 12c.621 0 1.125.504 1.125 1.125v1.5c0 .621-.504 1.125-1.125 1.125m-17.25 0h7.5M12 14.625v-1.5m0 1.5c0 .621-.504 1.125-1.125 1.125M12 14.625c0 .621.504 1.125 1.125 1.125m-2.25 0c.621 0 1.125.504 1.125 1.125m0 1.5v-1.5m0 0c0-.621.504-1.125 1.125-1.125m0 0h7.5" />
              </svg>
              <span class="hidden sm:block">Explore</span>
            </.link>
            <.link navigate={~p"/app/projects/#{@project.id}/transponders"} class="border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium">
              <svg class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M21 7.5l-2.25-1.313M21 7.5v2.25m0-2.25l-2.25 1.313M3 7.5l2.25-1.313M3 7.5l2.25 1.313M3 7.5v2.25m9 3l2.25-1.313M12 12.75l-2.25-1.313M12 12.75V15m0 6.75l2.25-1.313M12 21.75V19.5m0 2.25l-2.25-1.313m0-16.875L12 2.25l2.25 1.313M21 14.25v2.25l-2.25 1.313m-13.5 0L3 16.5v-2.25" />
              </svg>
              <span class="hidden sm:block">Transponders</span>
            </.link>
            <.link navigate={~p"/app/projects/#{@project.id}/tokens"} class="float-right border-teal-500 text-teal-600 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium" aria-current="page">
              <svg class="text-teal-400 group-hover:text-teal-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 5.25a3 3 0 013 3m3 0a6 6 0 01-7.029 5.912c-.563-.097-1.159.026-1.563.43L10.5 17.25H8.25v2.25H6v2.25H2.25v-2.818c0-.597.237-1.17.659-1.591l6.499-6.499c.404-.404.527-1 .43-1.563A6 6 0 1121.75 8.25z" />
              </svg>
              <span class="hidden sm:block">Tokens</span>
            </.link>
            <.link navigate={~p"/app/projects/#{@project.id}/settings"} class="float-right border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700 group inline-flex items-center border-b-2 py-4 px-1 text-sm font-medium">
              <svg class="text-gray-400 group-hover:text-gray-500 -ml-0.5 mr-2 h-5 w-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                <path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17L17.25 21A2.652 2.652 0 0021 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 11-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 004.486-6.336l-3.276 3.277a3.004 3.004 0 01-2.25-2.25l3.276-3.276a4.5 4.5 0 00-6.336 4.486c.091 1.076-.071 2.264-.904 2.95l-.102.085m-1.745 1.437L5.909 7.5H4.5L2.25 3.75l1.5-1.5L7.5 4.5v1.409l4.26 4.26m-1.745 1.437l1.745-1.437m6.615 8.206L15.75 15.75M4.867 19.125h.008v.008h-.008v-.008z" />
              </svg>
              <span class="hidden sm:block">Settings</span>
            </.link>
          </nav>
        </div>
      </div>
    </div>

    <%= if @is_new do %>
      <div class="relative z-10" aria-labelledby="slide-over-title" role="dialog" aria-modal="true">
        <!-- Background backdrop, show/hide based on slide-over state. -->
        <div class="fixed inset-0"></div>

        <div class="fixed inset-0 overflow-hidden">
          <div class="absolute inset-0 overflow-hidden">
            <div class="pointer-events-none fixed inset-y-0 right-0 flex max-w-full pl-10 sm:pl-16" x-transition:enter="transform transition ease-in-out duration-500 sm:duration-700" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0" x-transition:leave="transform transition ease-in-out duration-500 sm:duration-700" x-transition:leave-start="translate-x-0" x-transition:leave-end="translate-x-full">
              <div class="pointer-events-auto w-screen max-w-2xl">
                <%= if @token do %>
                  <div class="flex h-full flex-col overflow-y-scroll bg-white shadow-xl">
                    <div class="flex-1">
                      <!-- Header -->
                      <div class="bg-gray-50 px-4 py-6 sm:px-6">
                        <div class="flex items-start justify-between space-x-3">
                          <div class="space-y-1">
                            <h2 class="text-base font-semibold leading-6 text-gray-900" id="slide-over-title">New Token</h2>
                            <p class="text-sm text-gray-500">You've successfully created a Token!</p>
                          </div>
                          <div class="text-gray-400 hover:text-gray-500">
                            <.link navigate={~p"/app/projects/#{@project.id}/tokens"} class="">
                              <span class="sr-only">Close panel</span>
                              <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                              </svg>
                            </.link>
                          </div>
                        </div>
                      </div>

                      <!-- Container -->
                      <div class="space-y-6 py-6 sm:space-y-0 sm:divide-y sm:divide-gray-200 sm:py-0">
                        <div class="space-y-2 px-4 sm:grid sm:grid-cols-1 sm:gap-4 sm:space-y-0 sm:px-6 sm:py-5">

                          <div class="border-l-4 border-yellow-400 bg-yellow-50 p-4">
                            <div class="flex">
                              <div class="flex-shrink-0">
                                <svg class="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                                  <path fill-rule="evenodd" d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z" clip-rule="evenodd" />
                                </svg>
                              </div>
                              <div class="ml-3">
                                <p class="text-sm text-yellow-700">
                                  Please copy your token now as this is the last time you can access it.
                                </p>
                              </div>
                            </div>
                          </div>

                          <span id="project_token_token" class="rounded-md font-mono text-lg px-2 w-auto max-w-max break-normal text-red-700 bg-red-100"><%= @token.token %></span>

                          <span 
                            x-data="{ copied: false }"
                            class="cursor-pointer inline-flex items-center gap-2 text-sm font-medium text-gray-600 hover:text-gray-900"
                            phx-click={JS.dispatch("phx:copy", to: "#project_token_token")}
                            x-on:click="copied = true; setTimeout(() => copied = false, 3000)"
                          >
                            <!-- Copy Icon (show when not copied) -->
                            <svg x-show="!copied" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                              <path stroke-linecap="round" stroke-linejoin="round" d="M9 12h3.75M9 15h3.75M9 18h3.75m3 .75H18a2.25 2.25 0 002.25-2.25V6.108c0-1.135-.845-2.098-1.976-2.192a48.424 48.424 0 00-1.123-.08m-5.801 0c-.065.21-.1.433-.1.664 0 .414.336.75.75.75h4.5a.75.75 0 00.75-.75 2.25 2.25 0 00-.1-.664m-5.8 0A2.251 2.251 0 0113.5 2.25H15c1.012 0 1.867.668 2.15 1.586m-5.8 0c-.376.023-.75.05-1.124.08C9.095 4.01 8.25 4.973 8.25 6.108V8.25m0 0H4.875c-.621 0-1.125.504-1.125 1.125v11.25c0 .621.504 1.125 1.125 1.125h9.75c.621 0 1.125-.504 1.125-1.125V9.375c0-.621-.504-1.125-1.125-1.125H8.25zM6.75 12h.008v.008H6.75V12zm0 3h.008v.008H6.75V15zm0 3h.008v.008H6.75V18z" />
                            </svg>
                            
                            <!-- Check Icon (show when copied) -->
                            <svg x-show="copied" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 text-green-600">
                              <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                            </svg>
                            
                            <!-- Text -->
                            <span x-show="!copied">Copy</span>
                            <span x-show="copied" class="text-green-600">Copied</span>
                          </span>
                        </div>

                      </div>
                    </div>

                    <!-- Action buttons -->
                    <div class="flex-shrink-0 border-t border-gray-200 px-4 py-5 sm:px-6">
                      <div class="flex justify-end space-x-3">
                        <button phx-click="done" class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50">Done</button>
                      </div>
                    </div>
                  </div>
                <% else %>
                  <.form for={@form} phx-submit="create" class="flex h-full flex-col overflow-y-scroll bg-white shadow-xl">
                    <div class="flex-1">
                      <!-- Header -->
                      <div class="bg-gray-50 px-4 py-6 sm:px-6">
                        <div class="flex items-start justify-between space-x-3">
                          <div class="space-y-1">
                            <h2 class="text-base font-semibold leading-6 text-gray-900" id="slide-over-title">New Token</h2>
                            <p class="text-sm text-gray-500">Create new Token to access project programatically. You know, to push some data into it.</p>
                          </div>
                          <div class="text-gray-400 hover:text-gray-500">
                            <.link navigate={~p"/app/projects/#{@project.id}/tokens"} class="">
                              <span class="sr-only">Close panel</span>
                              <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" aria-hidden="true">
                                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                              </svg>
                            </.link>
                          </div>
                        </div>
                      </div>

                      <!-- Container -->
                      <div class="space-y-6 py-6 sm:space-y-0 sm:divide-y sm:divide-gray-200 sm:py-0">
                        <div class="space-y-2 px-4 sm:grid sm:grid-cols-3 sm:gap-4 sm:space-y-0 sm:px-6 sm:py-5">
                          <div>
                            <label for="project_token_name" class="block text-sm font-medium leading-6 text-gray-900 sm:mt-1.5">Name</label>
                          </div>
                          <div class="sm:col-span-2">
                            <.input field={@form[:name]} placeholder="" autocomplete="off" class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6" />
                          </div>
                        </div>

                        <div class="space-y-2 px-4 sm:grid sm:grid-cols-3 sm:gap-4 sm:space-y-0 sm:px-6 sm:py-5">
                          <div>
                            <label for="project_token_read" class="block text-sm font-medium leading-6 text-gray-900 sm:mt-1.5">Read Access</label>
                          </div>
                          <div class="sm:col-span-2">
                            <.input field={@form[:read]} type="checkbox" class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6" />
                          </div>
                        </div>

                        <div class="space-y-2 px-4 sm:grid sm:grid-cols-3 sm:gap-4 sm:space-y-0 sm:px-6 sm:py-5">
                          <div>
                            <label for="project_token_write" class="block text-sm font-medium leading-6 text-gray-900 sm:mt-1.5">Write Access</label>
                          </div>
                          <div class="sm:col-span-2">
                            <.input field={@form[:write]} type="checkbox" class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6" />
                          </div>
                        </div>
                      </div>
                    </div>

                    <!-- Action buttons -->
                    <div class="flex-shrink-0 border-t border-gray-200 px-4 py-5 sm:px-6">
                      <div class="flex justify-end space-x-3">
                        <.button phx-disable-with="Creating..." class="inline-flex justify-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600">Create</.button>
                        <.link navigate={~p"/app/projects/#{@project.id}/tokens"} class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50">Cancel</.link>
                      </div>
                    </div>
                  </.form>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <.link navigate={~p"/app/projects/#{@project.id}/tokens/new"} class="">New</.link>

    <div class="overflow-hidden bg-white shadow sm:rounded-md mt-4">
      <ul role="list" class="divide-y divide-gray-200">
        <%= for token <- @tokens do %>
          <li>
            <div class="block">
              <div class="flex items-center px-4 py-4 sm:px-6">
                <div class="min-w-0 flex-1 sm:flex sm:items-center sm:justify-between">
                  <div class="truncate">
                    <div class="flex text-sm">
                      <p class="truncate font-medium text-teal-600"><%= token.name %></p>
                      <p class="ml-1 flex-shrink-0 font-normal text-gray-500">ending <span class="text-red-500"><%= String.slice(token.token, -5, 5) %></span></p>
                    </div>
                    <div class="mt-2 flex">
                      <div class="flex items-center text-sm text-gray-500">
                        <!-- Heroicon name: mini/calendar -->
                        <svg class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                          <path fill-rule="evenodd" d="M5.75 2a.75.75 0 01.75.75V4h7V2.75a.75.75 0 011.5 0V4h.25A2.75 2.75 0 0118 6.75v8.5A2.75 2.75 0 0115.25 18H4.75A2.75 2.75 0 012 15.25v-8.5A2.75 2.75 0 014.75 4H5V2.75A.75.75 0 015.75 2zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75z" clip-rule="evenodd" />
                        </svg>
                        <p>
                        Last used
                          <time datetime="2020-01-07"><%= Calendar.strftime(token.updated_at, "%y-%m-%d %I:%M:%S %p")%></time>
                        </p>
                      </div>
                    </div>
                  </div>
                  <div class="mt-4 flex-shrink-0 sm:mt-0 sm:ml-5">
                    <div class="flex space-x-8 overflow-hidden">
                      <div class={if token.read, do: "text-green-600", else: "text-gray-300"}>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        Read
                      </div>

                      <div class={if token.write, do: "text-green-600", else: "text-gray-300"}>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                        </svg>
                        Write
                      </div>
                    </div>
                  </div>
                </div>
                <button class="ml-20 flex-shrink-0" phx-click="delete" phx-value-id={token.id} data-confirm="Are you sure?">
                  <svg class="h-5 w-5 text-teal-500 hover:text-teal-800" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 01-2.244 2.077H8.084a2.25 2.25 0 01-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 00-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 013.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 00-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 00-7.5 0" />
                  </svg>
                </button>
              </div>
            </div>
          </li>
        <% end %>
      </ul>
    </div>

    """
  end

  def mount(params, _session, socket) do
    is_new = socket.assigns.live_action == :new
    project = Organizations.get_project!(params["id"])
    tokens = Organizations.list_projects_project_tokens(project)
    changeset = Organizations.change_project_token(%ProjectToken{}, %{"project" => project})

    socket =
      assign(socket,
        page_title: (if is_new, do: ["Projects", project.name, "Tokens", "New"], else: ["Projects", project.name, "Tokens"]),
        is_new: is_new,
        project: project,
        tokens: tokens,
        token: nil,
        form: to_form(changeset)
      )

    {:ok, socket}
  end

  def handle_event("create", %{"project_token" => project_token_params}, socket) do
    case Organizations.create_projects_project_token(project_token_params, socket.assigns.project) do
      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
      {:ok, project_token} ->
        socket = socket
          |> assign(token: project_token)
          |> put_flash(:info, "Token created successfully.")
        {:noreply, socket}
    end
  end

  def handle_event("done", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/app/projects/#{socket.assigns.project.id}/tokens")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    token = Organizations.get_project_token!(id)
    Organizations.delete_project_token(token)

    socket = socket
      |> assign(tokens: Organizations.list_projects_project_tokens(socket.assigns.project))
      |> put_flash(:info, "Token deleted successfully.")
    {:noreply, socket}
  end
end
