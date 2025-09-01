defmodule TrifleApp.ProjectsLive do
  use TrifleApp, :live_view

  alias Trifle.Organizations
  alias Trifle.Organizations.Project

  def render(assigns) do
    ~H"""
    <%= if @is_new do %>
      <div class="relative z-10" aria-labelledby="slide-over-title" role="dialog" aria-modal="true">
        <!-- Background backdrop, show/hide based on slide-over state. -->
        <div class="fixed inset-0"></div>

        <div class="fixed inset-0 overflow-hidden">
          <div class="absolute inset-0 overflow-hidden">
            <div class="pointer-events-none fixed inset-y-0 right-0 flex max-w-full pl-10 sm:pl-16" x-transition:enter="transform transition ease-in-out duration-500 sm:duration-700" x-transition:enter-start="translate-x-full" x-transition:enter-end="translate-x-0" x-transition:leave="transform transition ease-in-out duration-500 sm:duration-700" x-transition:leave-start="translate-x-0" x-transition:leave-end="translate-x-full">
              <div class="pointer-events-auto w-screen max-w-2xl">
                <.form for={@form} phx-submit="create" class="flex h-full flex-col overflow-y-scroll bg-white shadow-xl">
                  <div class="flex-1">
                    <!-- Header -->
                    <div class="bg-gray-50 px-4 py-6 sm:px-6">
                      <div class="flex items-start justify-between space-x-3">
                        <div class="space-y-1">
                          <h2 class="text-base font-semibold leading-6 text-gray-900" id="slide-over-title">New Project</h2>
                          <p class="text-sm text-gray-500">Get started by filling in the information below to create your new project.</p>
                        </div>
                        <div class="text-gray-400 hover:text-gray-500">
                          <.link navigate={~p"/app/projects"} class="">
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
                          <label for="project_name" class="block text-sm font-medium leading-6 text-gray-900 sm:mt-1.5">Project Name</label>
                        </div>
                        <div class="sm:col-span-2">
                          <.input field={@form[:name]} placeholder="Secret weather station" autocomplete="off" class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6" />
                        </div>
                      </div>

                      <div class="space-y-2 px-4 sm:grid sm:grid-cols-3 sm:gap-4 sm:space-y-0 sm:px-6 sm:py-5">
                        <div>
                          <label for="project_time_zone" class="block text-sm font-medium leading-6 text-gray-900 sm:mt-1.5">Time Zone</label>
                        </div>
                        <div class="sm:col-span-2">
                          <.input field={@form[:time_zone]} type="select" options={@time_zones} class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6" />
                        </div>
                      </div>

                      <div class="space-y-2 px-4 sm:grid sm:grid-cols-3 sm:gap-4 sm:space-y-0 sm:px-6 sm:py-5">
                        <div>
                          <label for="project_beginning_of_week" class="block text-sm font-medium leading-6 text-gray-900 sm:mt-1.5">Beginning of Week</label>
                        </div>
                        <div class="sm:col-span-2">
                          <.input field={@form[:beginning_of_week]} type="select" options={[{"Monday", 1}, {"Tuesday", 2}, {"Wednesday", 3}, {"Thursday", 4}, {"Friday", 5}, {"Saturday", 6}, {"Sunday", 7}]} class="block w-full rounded-md border-0 py-1.5 text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 placeholder:text-gray-400 focus:ring-2 focus:ring-inset focus:ring-teal-600 sm:text-sm sm:leading-6" />
                        </div>
                      </div>
                    </div>
                  </div>

                  <!-- Action buttons -->
                  <div class="flex-shrink-0 border-t border-gray-200 px-4 py-5 sm:px-6">
                    <div class="flex justify-end space-x-3">
                      <.button phx-disable-with="Creating..." class="inline-flex justify-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-teal-600">Create</.button>
                      <.link navigate={~p"/app/projects"} class="rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50">Cancel</.link>
                    </div>
                  </div>
                 </.form>
              </div>
            </div>
          </div>
        </div>
      </div>
    <% end %>

    <.link navigate={~p"/app/projects/new"} class="">New</.link>

    <div class="overflow-hidden bg-white shadow sm:rounded-md mt-4">
      <ul role="list" class="divide-y divide-gray-200">
        <%= for project <- @projects do %>
          <li>
            <.link navigate={~p"/app/projects/#{project.id}"} class="block hover:bg-gray-50">
              <div class="flex items-center px-4 py-4 sm:px-6">
                <div class="min-w-0 flex-1 sm:flex sm:items-center sm:justify-between">
                  <div class="truncate">
                    <div class="flex text-sm">
                      <p class="truncate font-medium text-teal-600"><%= project.name %></p>
                      <p class="ml-1 flex-shrink-0 font-normal text-gray-500">as <span class="text-red-500"><%= project.slug %></span></p>
                    </div>
                    <div class="mt-2 flex">
                      <div class="flex items-center text-sm text-gray-500">
                        <!-- Heroicon name: mini/calendar -->
                        <svg class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                          <path fill-rule="evenodd" d="M5.75 2a.75.75 0 01.75.75V4h7V2.75a.75.75 0 011.5 0V4h.25A2.75 2.75 0 0118 6.75v8.5A2.75 2.75 0 0115.25 18H4.75A2.75 2.75 0 012 15.25v-8.5A2.75 2.75 0 014.75 4H5V2.75A.75.75 0 015.75 2zm-1 5.5c-.69 0-1.25.56-1.25 1.25v6.5c0 .69.56 1.25 1.25 1.25h10.5c.69 0 1.25-.56 1.25-1.25v-6.5c0-.69-.56-1.25-1.25-1.25H4.75z" clip-rule="evenodd" />
                        </svg>
                        <p>
                        Last data received at
                          <time datetime="2020-01-07">January 7, 2020</time>
                        </p>
                      </div>
                    </div>
                  </div>
                  <div class="mt-4 flex-shrink-0 sm:mt-0 sm:ml-5">
                    <div class="flex -space-x-1 overflow-hidden">
                      <img class="inline-block h-6 w-6 rounded-full ring-2 ring-white" src="https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&auto=format&fit=facearea&facepad=2&w=256&h=256&q=80" alt="Dries Vincent">

                    </div>
                  </div>
                </div>
                <div class="ml-5 flex-shrink-0">
                  <!-- Heroicon name: mini/chevron-right -->
                  <svg class="h-5 w-5 text-gray-400" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                    <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
                  </svg>
                </div>
              </div>
            </.link>
          </li>
        <% end %>
      </ul>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    is_new = socket.assigns.live_action == :new
    projects = Organizations.list_users_projects(socket.assigns.current_user)
    changeset = Organizations.change_project(%Project{})

    socket =
      assign(socket,
        page_title: (if is_new, do: ["Projects", "New"], else: ["Projects"]),
        projects: projects,
        is_new: is_new,
        form: to_form(changeset),
        time_zones: time_zones()
      )

    {:ok, socket}
  end

  def time_zones do
    now = DateTime.utc_now()

    Tzdata.zone_list()
    |> Enum.map(fn zone ->
      tzinfo = Timex.Timezone.get(zone, now)
      offset = Timex.TimezoneInfo.format_offset(tzinfo)
      label = "#{tzinfo.full_name} - #{tzinfo.abbreviation} (#{offset})"

      {label, tzinfo.full_name}
    end)
    |> Enum.uniq()
  end

  def handle_event("create", %{"project" => project_params}, socket) do
    case Organizations.create_users_project(project_params, socket.assigns.current_user) do
      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:ok, _project} ->
        {:noreply, push_navigate(socket, to: ~p"/app/projects")}
    end
  end
end
