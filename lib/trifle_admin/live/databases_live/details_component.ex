defmodule TrifleAdmin.DatabasesLive.DetailsComponent do
  use TrifleAdmin, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="pb-6">
        <div class="flex items-center justify-between">
          <div>
            <h3 class="text-base/7 font-semibold text-gray-900">{@database.display_name}</h3>
            <p class="mt-1 max-w-2xl text-sm/6 text-gray-500">
              {String.capitalize(@database.driver)} database connection
            </p>
          </div>
          <span class={status_badge_class(@database.last_check_status)}>
            {status_text(@database.last_check_status)}
          </span>
        </div>
      </div>
      <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
        <dl class="divide-y divide-gray-200 dark:divide-slate-600">
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Organization</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
              {(@database.organization && @database.organization.name) || "N/A"}
            </dd>
          </div>
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Driver</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
              <.database_label driver={@database.driver} />
            </dd>
          </div>

          <%= if @database.host do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Host</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono">
                {@database.host}{if @database.port, do: ":#{@database.port}"}
              </dd>
            </div>
          <% end %>

          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">
              <%= cond do %>
                <% @database.driver == "sqlite" -> %>
                  Database file
                <% @database.driver == "redis" -> %>
                  Database
                <% true -> %>
                  Database name
              <% end %>
            </dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0 font-mono break-all">
              <%= cond do %>
                <% @database.driver == "sqlite" -> %>
                  {@database.file_path || "N/A"}
                <% @database.driver == "redis" -> %>
                  Default (0)
                <% true -> %>
                  {@database.database_name || "N/A"}
              <% end %>
            </dd>
          </div>

          <%= if @database.username do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Username</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {@database.username}
              </dd>
            </div>
          <% end %>

          <%= if @database.last_check_at do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">Last checked</dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {Calendar.strftime(@database.last_check_at, "%B %d, %Y at %I:%M %p UTC")}
              </dd>
            </div>
          <% end %>
          
    <!-- Granularities -->
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Time granularities</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
              <%= if @database.granularities && length(@database.granularities) > 0 do %>
                <div class="flex flex-wrap gap-1">
                  <%= for granularity <- @database.granularities do %>
                    <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                      {granularity}
                    </span>
                  <% end %>
                </div>
              <% else %>
                <span class="text-gray-500">Using defaults (1m, 1h, 1d, 1w, 1mo, 1q, 1y)</span>
              <% end %>
            </dd>
          </div>
          
    <!-- Time Zone -->
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Time Zone</dt>
            <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
              {@database.time_zone || "UTC"}
            </dd>
          </div>
          
    <!-- Defaults -->
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Default Timeframe</dt>
            <dd class="mt-1 sm:col-span-2 sm:mt-0">
              <%= if @database.default_timeframe && @database.default_timeframe != "" do %>
                <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                  {@database.default_timeframe}
                </span>
              <% else %>
                <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
              <% end %>
            </dd>
          </div>
          <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
            <dt class="text-sm font-medium text-gray-900 dark:text-white">Default Granularity</dt>
            <dd class="mt-1 sm:col-span-2 sm:mt-0">
              <%= if @database.default_granularity && @database.default_granularity != "" do %>
                <span class="inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                  {@database.default_granularity}
                </span>
              <% else %>
                <span class="text-sm text-gray-500 dark:text-slate-400">Not set</span>
              <% end %>
            </dd>
          </div>

          <%= for {key, value} <- (@database.config || %{}) do %>
            <div class="py-4 sm:grid sm:grid-cols-3 sm:gap-4">
              <dt class="text-sm font-medium text-gray-900 dark:text-white">
                {humanize_config_key(key)}
              </dt>
              <dd class="mt-1 text-sm/6 text-gray-700 dark:text-slate-300 sm:col-span-2 sm:mt-0">
                {format_config_value(value)}
              </dd>
            </div>
          <% end %>
        </dl>
      </div>

      <%= if @database.last_error do %>
        <div class="border-t border-gray-200 dark:border-slate-600 pt-6">
          <div class="rounded-md bg-red-50 dark:bg-red-900/20 p-4">
            <div class="flex">
              <div class="flex-shrink-0">
                <svg
                  class="h-5 w-5 text-red-400"
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path
                    fill-rule="evenodd"
                    d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.28 7.22a.75.75 0 00-1.06 1.06L8.94 10l-1.72 1.72a.75.75 0 101.06 1.06L10 11.06l1.72 1.72a.75.75 0 101.06-1.06L11.06 10l1.72-1.72a.75.75 0 00-1.06-1.06L10 8.94 8.28 7.22z"
                    clip-rule="evenodd"
                  />
                </svg>
              </div>
              <div class="ml-3">
                <h3 class="text-sm font-medium text-red-800">Connection Error</h3>
                <div class="mt-2 text-sm text-red-700">
                  <p>{@database.last_error}</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_badge_class("success"),
    do:
      "inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20"

  defp status_badge_class("error"),
    do:
      "inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20"

  defp status_badge_class("pending"),
    do:
      "inline-flex items-center rounded-md bg-yellow-50 px-2 py-1 text-xs font-medium text-yellow-800 ring-1 ring-inset ring-yellow-600/20"

  defp status_badge_class(_),
    do:
      "inline-flex items-center rounded-md bg-gray-50 px-2 py-1 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10"

  defp status_text("success"), do: "Connected"
  defp status_text("error"), do: "Error"
  defp status_text("pending"), do: "Pending"
  defp status_text(_), do: "Unknown"

  defp humanize_config_key(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_config_value(nil), do: "Not set"
  defp format_config_value(true), do: "Enabled"
  defp format_config_value(false), do: "Disabled"
  defp format_config_value(value) when is_binary(value), do: value
  defp format_config_value(value), do: to_string(value)
end
