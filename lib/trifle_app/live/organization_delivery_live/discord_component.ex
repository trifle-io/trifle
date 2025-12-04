defmodule TrifleApp.OrganizationDeliveryLive.DiscordComponent do
  use TrifleApp, :live_component

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :discord_info, :map, required: true
  attr :discord_installations, :list, default: []
  attr :can_manage, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-lg overflow-hidden border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-sm"
    >
      <button
        id={"#{@id}-trigger"}
        type="button"
        class="group w-full px-4 py-3 flex items-center justify-between gap-4 text-left transition-colors hover:bg-gray-50 dark:hover:bg-slate-700/40"
        phx-click={toggle_panel(@id)}
        aria-controls={"#{@id}-body"}
      >
        <div class="flex w-full items-start justify-between">
          <div class="flex items-start gap-3">
            <div class={chip_class(@status)} aria-hidden="true"></div>
            <div>
              <div class="flex items-center gap-2">
                <span class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-indigo-600 dark:group-hover:text-indigo-300">
                  Discord
                </span>
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  badge_class(@status)
                ]}>
                  {status_label(@status)}
                </span>
              </div>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Send alerts and reports to Discord servers and channels your team already uses.
              </p>
            </div>
          </div>
          <.icon
            name="hero-chevron-down-mini"
            id={"#{@id}-chevron"}
            class="h-5 w-5 text-gray-400 transition-transform duration-150"
          />
        </div>
      </button>

      <div
        id={"#{@id}-body"}
        class="hidden border-t border-gray-200 dark:border-slate-700 px-4 py-5 space-y-5"
      >
        <div
          :if={!@discord_info.configured?}
          class="rounded-lg border border-amber-200 bg-amber-50/80 px-4 py-4 text-sm text-amber-900 dark:border-amber-400/40 dark:bg-amber-500/10 dark:text-amber-200"
        >
          <p class="font-semibold text-amber-900 dark:text-amber-200">
            Connect a Discord bot to enable channel delivery.
          </p>
          <p class="mt-2 leading-relaxed">
            One Discord application can serve all of your Trifle organizations. After the bot is configured you can authorize multiple servers and map their channels to references such as <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs text-amber-900 dark:text-amber-200">discord_server#alerts</code>.
          </p>
          <ol class="mt-3 list-decimal space-y-2 pl-5">
            <li>
              Visit
              <a
                href="https://discord.com/developers/applications"
                target="_blank"
                rel="noreferrer noopener"
                class="underline decoration-amber-500/60 hover:text-amber-700 dark:hover:text-amber-100"
              >
                discord.com/developers/applications
              </a>
              and create a new application. Add a Bot user and copy the <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">Client ID</code>, <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">Client Secret</code>, and <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">Bot Token</code>.
            </li>
            <li>
              Under <strong>OAuth2</strong>
              add the redirect URL <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">{@discord_info.settings.redirect_uri}</code>.
            </li>
            <li>
              Enable scopes <code>bot</code>, <code>applications.commands</code>, <code>identify</code>, and <code>guilds</code>. Grant the bot permissions to view channels, send messages, embed links, and attach files.
            </li>
            <li>
              Update your Helm values with:
              <div class="mt-2 rounded border border-amber-200 bg-white/70 dark:border-amber-400/30 dark:bg-slate-900/50 p-3 text-xs text-gray-700 dark:text-slate-200">
                <p><code>app.discord.clientId</code> = <em>Client ID</em></p>
                <p><code>app.discord.clientSecret</code> = <em>Client Secret</em></p>
                <p><code>app.discord.botToken</code> = <em>Bot Token</em></p>
                <p><code>app.discord.redirectUri</code> = <em>Redirect URL above</em></p>
                <p class="mt-1 text-[11px] text-gray-500 dark:text-slate-400">
                  Optional: <code>app.discord.scopes</code>, <code>app.discord.permissions</code>
                </p>
              </div>
            </li>
            <li>
              Redeploy so the release picks up the new environment variables.
            </li>
          </ol>
          <p class="mt-3 leading-relaxed">
            When the environment variables are present this panel unlocks the workflow for authorizing servers and selecting delivery targets.
          </p>
        </div>

        <div
          :if={@discord_info.configured?}
          class="space-y-5 text-sm text-gray-700 dark:text-slate-200"
        >
          <div class="rounded-lg border border-indigo-200 bg-indigo-50/80 px-4 py-3 text-indigo-900 dark:border-indigo-500/30 dark:bg-indigo-500/10 dark:text-indigo-200">
            <p class="font-medium">
              Discord credentials detected. Reference channels with <code class="rounded bg-white/80 dark:bg-slate-700/80 px-1 py-0.5 text-xs text-indigo-700 dark:text-indigo-200">discord_server#channel</code>.
            </p>
            <p class="mt-2 leading-relaxed">
              One Discord bot can join multiple servers. Each server you connect exposes its text channels as delivery targets.
            </p>
          </div>

          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div class="text-sm text-gray-600 dark:text-slate-300">
              <p>
                Connect a server, then enable the channels you want to deliver to. References follow <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs text-gray-700 dark:text-slate-200">discord_server#channel</code>.
              </p>
            </div>
            <div class="flex items-center gap-3">
              <%= if @can_manage do %>
                <.primary_button
                  type="button"
                  phx-click="connect_discord"
                  phx-disable-with="Redirecting..."
                  class="gap-2"
                >
                  <.icon name="hero-plus-small" class="h-4 w-4" /> Connect Discord server
                </.primary_button>
              <% else %>
                <span class="text-xs text-gray-500 dark:text-slate-400">
                  Only organization admins can connect or manage Discord servers.
                </span>
              <% end %>
            </div>
          </div>

          <div
            :if={Enum.empty?(@discord_installations)}
            class="rounded-lg border border-gray-200 dark:border-slate-700 px-4 py-4 text-sm"
          >
            <p class="font-medium text-gray-800 dark:text-white">No servers connected yet</p>
            <p class="mt-1 text-gray-600 dark:text-slate-300">
              Use “Connect Discord server” to start the OAuth handshake. After Discord redirects back you'll be able to sync channels and enable delivery targets.
            </p>
          </div>

          <div :if={Enum.any?(@discord_installations)} class="space-y-4">
            <%= for installation <- @discord_installations do %>
              <% enabled_count = Enum.count(installation.channels || [], & &1.enabled) %>
              <% total_count = length(installation.channels || []) %>
              <div class="rounded-lg border border-gray-200 dark:border-slate-700 px-4 py-4">
                <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                  <div class="space-y-1">
                    <p class="text-sm font-semibold text-gray-900 dark:text-white">
                      {installation.guild_name}
                    </p>
                    <p class="text-xs text-gray-500 dark:text-slate-400">
                      Reference prefix:
                      <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs text-gray-700 dark:text-slate-200">
                        {reference_prefix(installation)}
                      </code>
                    </p>
                    <p class="text-xs text-gray-500 dark:text-slate-400">
                      {enabled_count} enabled / {total_count} channel{if total_count == 1,
                        do: "",
                        else: "s"} • {format_sync_time(installation.last_channel_sync_at)}
                    </p>
                  </div>
                  <div :if={@can_manage} class="flex flex-col gap-2 sm:flex-row sm:items-center">
                    <.primary_button
                      type="button"
                      class="bg-slate-800 hover:bg-slate-700 dark:bg-slate-700 dark:hover:bg-slate-600"
                      phx-click="sync_discord"
                      phx-value-id={installation.id}
                      phx-disable-with="Syncing..."
                    >
                      <.icon name="hero-arrow-path" class="h-4 w-4" /> Sync channels
                    </.primary_button>
                    <button
                      type="button"
                      class="inline-flex items-center justify-center rounded-md border border-red-300 px-3 py-1.5 text-xs font-medium text-red-600 transition hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:border-red-500/60 dark:text-red-300 dark:hover:bg-red-500/10 dark:focus:ring-offset-slate-900"
                      phx-click="remove_discord_installation"
                      phx-value-id={installation.id}
                      data-confirm="Disconnect {installation.guild_name}? This removes access for all channels."
                    >
                      Remove server
                    </button>
                  </div>
                </div>

                <div class="mt-4 rounded-lg border border-gray-200 dark:border-slate-700">
                  <div class="px-3 py-2 text-xs font-medium uppercase tracking-wide text-gray-500 dark:text-slate-400">
                    Channels
                  </div>
                  <div
                    :if={total_count == 0}
                    class="px-4 py-6 text-sm text-gray-500 dark:text-slate-400"
                  >
                    No channels discovered yet. Run a sync after completing the Discord authorization.
                  </div>
                  <div :if={total_count > 0} class="divide-y divide-gray-200 dark:divide-slate-700">
                    <%= for channel <- installation.channels || [] do %>
                      <div class="px-4 py-3">
                        <div class="flex gap-3">
                          <div class={channel_indicator_class(channel)} aria-hidden="true"></div>
                          <div class="flex-1 space-y-2 sm:flex sm:items-center sm:justify-between sm:space-y-0">
                            <div class="space-y-1">
                              <div class="flex flex-wrap items-center gap-2">
                                <span class="text-sm font-medium text-gray-800 dark:text-white flex items-center gap-2">
                                  <span class="text-gray-500 dark:text-slate-300">#</span>
                                  {channel.name}
                                </span>
                                <span class={[
                                  "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide border border-gray-200 dark:border-slate-700",
                                  channel_type_class(channel)
                                ]}>
                                  {channel_type_label(channel)}
                                </span>
                              </div>
                              <p class="text-xs text-gray-500 dark:text-slate-400">
                                Deliver with:
                                <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs text-gray-700 dark:text-slate-200">
                                  {channel_reference(installation, channel)}
                                </code>
                              </p>
                            </div>
                            <div class="flex items-center gap-3">
                              <span class={channel_status_class(channel.enabled)}>
                                {channel_status(channel.enabled)}
                              </span>
                              <%= if @can_manage do %>
                                <button
                                  type="button"
                                  class={[
                                    "inline-flex items-center justify-center rounded-md border px-3 py-1.5 text-xs font-medium transition focus:outline-none focus:ring-2 focus:ring-offset-2",
                                    channel.enabled &&
                                      "border-gray-300 text-gray-700 hover:bg-gray-50 focus:ring-indigo-500 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-700 dark:focus:ring-indigo-500 dark:focus:ring-offset-slate-900",
                                    !channel.enabled &&
                                      "border-indigo-300 text-indigo-700 hover:bg-indigo-50 focus:ring-indigo-500 dark:border-indigo-500/50 dark:text-indigo-200 dark:hover:bg-indigo-500/10 dark:focus:ring-indigo-500 dark:focus:ring-offset-slate-900"
                                  ]}
                                  phx-click="toggle_discord_channel"
                                  phx-value-id={channel.id}
                                  phx-value-next={toggle_value(channel.enabled)}
                                  phx-value-installation-id={installation.id}
                                >
                                  <%= if channel.enabled do %>
                                    Disable
                                  <% else %>
                                    Enable
                                  <% end %>
                                </button>
                              <% else %>
                                <span class="text-xs text-gray-500 dark:text-slate-400">
                                  Ask an admin to change access.
                                </span>
                              <% end %>
                            </div>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_panel(id) do
    JS.toggle(to: "##{id}-body")
    |> JS.toggle_class("rotate-180", to: "##{id}-chevron")
  end

  defp chip_class(:ok),
    do: "flex-none h-10 w-1.5 rounded bg-emerald-500/90 dark:bg-emerald-400/80"

  defp chip_class(:warning),
    do: "flex-none h-10 w-1.5 rounded bg-amber-500/80 dark:bg-amber-400/70"

  defp chip_class(:error),
    do: "flex-none h-10 w-1.5 rounded bg-rose-500/80 dark:bg-rose-400/70"

  defp badge_class(:ok),
    do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300"

  defp badge_class(:warning),
    do: "bg-amber-100 text-amber-700 dark:bg-amber-500/10 dark:text-amber-200"

  defp badge_class(:error),
    do: "bg-rose-100 text-rose-700 dark:bg-rose-500/10 dark:text-rose-200"

  defp status_label(:ok), do: "Ready"
  defp status_label(:warning), do: "Needs configuration"
  defp status_label(:error), do: "Not connected"

  defp reference_prefix(installation), do: "discord_#{installation.reference}"

  defp channel_reference(installation, channel),
    do: "#{reference_prefix(installation)}##{channel.name}"

  defp channel_indicator_class(%{enabled: true}),
    do: "flex-none h-10 w-1.5 rounded bg-emerald-500/90 dark:bg-emerald-400/80"

  defp channel_indicator_class(_),
    do: "flex-none h-10 w-1.5 rounded bg-gray-300 dark:bg-slate-600"

  defp channel_status_class(true),
    do:
      "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide bg-emerald-100 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-200"

  defp channel_status_class(false),
    do:
      "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide bg-gray-100 text-gray-600 dark:bg-slate-700/70 dark:text-slate-300"

  defp channel_status(true), do: "Enabled"
  defp channel_status(false), do: "Disabled"

  defp channel_type_label(%{channel_type: "announcement"}), do: "Announcement"
  defp channel_type_label(%{channel_type: "text"}), do: "Text"

  defp channel_type_label(%{channel_type: other}) when is_binary(other) do
    other
    |> String.replace("_", " ")
    |> String.downcase()
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp channel_type_label(_), do: "Channel"

  defp channel_type_class(%{channel_type: "announcement"}),
    do: "bg-sky-100 text-sky-700 dark:bg-sky-500/10 dark:text-sky-200"

  defp channel_type_class(%{channel_type: "text"}),
    do: "bg-indigo-100 text-indigo-700 dark:bg-indigo-500/10 dark:text-indigo-200"

  defp channel_type_class(%{channel_type: other}) when is_binary(other) do
    downcased = String.downcase(other || "")

    cond do
      String.contains?(downcased, "text") ->
        "bg-indigo-100 text-indigo-700 dark:bg-indigo-500/10 dark:text-indigo-200"

      true ->
        "bg-slate-100 text-slate-600 dark:bg-slate-700/70 dark:text-slate-300"
    end
  end

  defp channel_type_class(_),
    do: "bg-slate-100 text-slate-600 dark:bg-slate-700/70 dark:text-slate-300"

  defp toggle_value(true), do: "false"
  defp toggle_value(false), do: "true"

  defp format_sync_time(nil), do: "Not synced yet"

  defp format_sync_time(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%b %-d, %Y %H:%M UTC")
  rescue
    _ -> "Last synced recently"
  end
end
