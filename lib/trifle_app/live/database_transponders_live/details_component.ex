defmodule TrifleApp.DatabaseTranspondersLive.DetailsComponent do
  use TrifleApp, :live_component

  alias Trifle.Organizations.Transponder

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@transponder.key}
        <:subtitle>View transponder details and configuration.</:subtitle>
        <:actions>
          <.link
            patch={~p"/dbs/#{@database.id}/transponders/#{@transponder.id}/edit"}
            class="inline-flex items-center rounded-md bg-teal-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-teal-500"
          >
            <svg class="-ml-0.5 mr-1.5 h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
              <path d="m5.433 13.917 1.262-3.155A4 4 0 0 1 7.58 9.42l6.92-6.918a2.121 2.121 0 0 1 3 3l-6.92 6.918c-.383.383-.84.685-1.343.886l-3.154 1.262a.5.5 0 0 1-.65-.65Z" />
              <path d="M3.5 5.75c0-.69.56-1.25 1.25-1.25H10A.75.75 0 0 0 10 3H4.75A2.75 2.75 0 0 0 2 5.75v9.5A2.75 2.75 0 0 0 4.75 18h9.5A2.75 2.75 0 0 0 17 15.25V10a.75.75 0 0 0-1.5 0v5.25c0 .69-.56 1.25-1.25 1.25h-9.5c-.69 0-1.25-.56-1.25-1.25v-9.5Z" />
            </svg>
            Edit
          </.link>
        </:actions>
      </.header>

      <div class="mt-6">
        <dl class="grid grid-cols-1 gap-x-4 gap-y-6 sm:grid-cols-2">
          <div>
            <dt class="text-sm font-medium leading-6 text-gray-900 dark:text-white">Type</dt>
            <dd class="mt-1 text-sm leading-6 text-gray-700 dark:text-gray-300">
              {Transponder.get_type_display_name(@transponder.type)}
            </dd>
          </div>

          <div>
            <dt class="text-sm font-medium leading-6 text-gray-900 dark:text-white">Status</dt>
            <dd class="mt-1 text-sm leading-6 text-gray-700 dark:text-gray-300">
              <%= if @transponder.enabled do %>
                <span class="inline-flex items-center rounded-full bg-green-100 dark:bg-green-900/20 px-2.5 py-0.5 text-xs font-medium text-green-800 dark:text-green-300">
                  Enabled
                </span>
              <% else %>
                <span class="inline-flex items-center rounded-full bg-gray-100 dark:bg-slate-700 px-2.5 py-0.5 text-xs font-medium text-gray-800 dark:text-gray-300">
                  Disabled
                </span>
              <% end %>
            </dd>
          </div>

          <%= if not Enum.empty?(@transponder.config) do %>
            <div class="sm:col-span-2">
              <dt class="text-sm font-medium leading-6 text-gray-900 dark:text-white">
                Configuration
              </dt>
              <dd class="mt-2">
                <div class="overflow-hidden bg-gray-50 dark:bg-slate-700 shadow sm:rounded-lg">
                  <div class="px-4 py-5 sm:p-6">
                    <dl class="grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2">
                      <%= for {key, value} <- @transponder.config do %>
                        <div>
                          <dt class="text-sm font-medium text-gray-500 dark:text-slate-400">
                            {String.capitalize(String.replace(to_string(key), "_", " "))}
                          </dt>
                          <dd class="mt-1 text-sm text-gray-900 dark:text-white">{value}</dd>
                        </div>
                      <% end %>
                    </dl>
                  </div>
                </div>
              </dd>
            </div>
          <% end %>

          <div>
            <dt class="text-sm font-medium leading-6 text-gray-900 dark:text-white">Created</dt>
            <dd class="mt-1 text-sm leading-6 text-gray-700 dark:text-gray-300">
              {Calendar.strftime(@transponder.inserted_at, "%B %d, %Y at %I:%M %p")}
            </dd>
          </div>

          <div>
            <dt class="text-sm font-medium leading-6 text-gray-900 dark:text-white">Last Updated</dt>
            <dd class="mt-1 text-sm leading-6 text-gray-700 dark:text-gray-300">
              {Calendar.strftime(@transponder.updated_at, "%B %d, %Y at %I:%M %p")}
            </dd>
          </div>
        </dl>
      </div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end
end
