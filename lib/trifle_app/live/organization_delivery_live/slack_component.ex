defmodule TrifleApp.OrganizationDeliveryLive.SlackComponent do
  use TrifleApp, :live_component

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :slack_info, :map, required: true
  attr :slack_installations, :list, default: []
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
                <span class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-300">
                  Slack
                </span>
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  badge_class(@status)
                ]}>
                  {status_label(@status)}
                </span>
              </div>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Deliver alerts into Slack workspaces and channels of your choice.
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
          :if={!@slack_info.configured?}
          class="rounded-lg border border-amber-200 bg-amber-50/80 px-4 py-4 text-sm text-amber-900 dark:border-amber-400/40 dark:bg-amber-500/10 dark:text-amber-200"
        >
          <p class="font-semibold text-amber-900 dark:text-amber-200">
            Connect your own Slack application to enable channel delivery.
          </p>
          <p class="mt-2 leading-relaxed">
            You only need one Slack App for Trifle. After the app is configured you can authorize multiple Slack workspaces
            and map their channels to references such as <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs text-amber-900 dark:text-amber-200">slack_workspace#incident-room</code>.
          </p>
          <ol class="mt-3 list-decimal space-y-2 pl-5">
            <li>
              Visit
              <a
                href="https://api.slack.com/apps"
                target="_blank"
                rel="noreferrer noopener"
                class="underline decoration-amber-500/60 hover:text-amber-700 dark:hover:text-amber-100"
              >
                api.slack.com/apps
              </a>
              and create a new app <em>from scratch</em>.
            </li>
            <li>
              Under <strong>Basic Information</strong>, copy the <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">Client ID</code>, <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">Client Secret</code>, and <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">Signing Secret</code>.
            </li>
            <li>
              Navigate to <strong>OAuth &amp; Permissions</strong>
              and add the redirect URL <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">{@slack_info.settings.redirect_uri}</code>.
            </li>
            <li>
              Add the following bot scopes: <code>chat:write</code>, <code>chat:write.public</code>, <code>channels:read</code>, <code>groups:read</code>, and <code>incoming-webhook</code>. You can add more scopes later if needed.
            </li>
            <li>
              Update your Helm values with:
              <div class="mt-2 rounded border border-amber-200 bg-white/70 dark:border-amber-400/30 dark:bg-slate-900/50 p-3 text-xs text-gray-700 dark:text-slate-200">
                <p><code>app.slack.clientId</code> = <em>Client ID</em></p>
                <p><code>app.slack.clientSecret</code> = <em>Client Secret</em></p>
                <p><code>app.slack.signingSecret</code> = <em>Signing Secret</em></p>
                <p><code>app.slack.redirectUri</code> = <em>Redirect URL above</em></p>
              </div>
            </li>
            <li>
              Redeploy the chart so the release picks up the new environment variables.
            </li>
          </ol>
          <p class="mt-3 leading-relaxed">
            When the environment variables are present this panel will unlock the workflow for authorizing workspaces and selecting delivery channels.
          </p>
        </div>

        <div :if={@slack_info.configured?} class="space-y-5 text-sm text-gray-700 dark:text-slate-200">
          <div
            :if={@status == :error}
            class="rounded-lg border border-rose-200 bg-rose-50/80 px-4 py-3 text-rose-900 dark:border-rose-500/40 dark:bg-rose-500/10 dark:text-rose-200"
          >
            <p class="font-medium">Slack reported a configuration issue.</p>
            <p class="mt-1 leading-relaxed text-xs">
              Re-run workspace sync and review your Helm values for typos. If the issue persists, redeploy with a fresh client secret and check the app logs for Slack error codes.
            </p>
          </div>

          <div class="rounded-lg border border-emerald-200 bg-emerald-50/70 px-4 py-3 text-emerald-800 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-200">
            <p class="font-medium">
              Slack credentials detected. Authorize workspaces and reference channels with the pattern <code class="rounded bg-white/80 dark:bg-slate-700/80 px-1 py-0.5 text-xs text-emerald-700 dark:text-emerald-200">slack_workspace#channel-name</code>.
            </p>
            <p class="mt-2 leading-relaxed">
              One Slack app can authorize multiple workspaces. Each workspace you connect can expose several channels as delivery targets.
            </p>
          </div>

          <div class="flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
            <div class="text-sm text-gray-600 dark:text-slate-300">
              <p>
                Connect a workspace to authorize Trifle, then enable the channels you want to deliver to. References follow <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs text-gray-700 dark:text-slate-200">slack_workspace#channel</code>.
              </p>
            </div>
            <div class="flex items-center gap-3">
              <%= if @can_manage do %>
                <.primary_button
                  type="button"
                  phx-click="connect_slack"
                  phx-disable-with="Redirecting..."
                  class="gap-2"
                >
                  <.icon name="hero-plus-small" class="h-4 w-4" /> Connect Slack workspace
                </.primary_button>
              <% else %>
                <span class="text-xs text-gray-500 dark:text-slate-400">
                  Only organization admins can connect or manage Slack workspaces.
                </span>
              <% end %>
            </div>
          </div>

          <div
            :if={Enum.empty?(@slack_installations)}
            class="rounded-lg border border-gray-200 dark:border-slate-700 px-4 py-4 text-sm"
          >
            <p class="font-medium text-gray-800 dark:text-white">No workspaces connected yet</p>
            <p class="mt-1 text-gray-600 dark:text-slate-300">
              Use “Connect Slack workspace” to start the OAuth handshake. After Slack redirects back here you'll be able to sync channels and enable delivery targets.
            </p>
          </div>

          <div :if={Enum.any?(@slack_installations)} class="space-y-4">
            <%= for installation <- @slack_installations do %>
              <% enabled_count = Enum.count(installation.channels || [], & &1.enabled) %>
              <% total_count = length(installation.channels || []) %>
              <div class="rounded-lg border border-gray-200 dark:border-slate-700 px-4 py-4">
                <div class="flex flex-col gap-3 lg:flex-row lg:items-start lg:justify-between">
                  <div class="space-y-1">
                    <p class="text-sm font-semibold text-gray-900 dark:text-white">
                      {installation.team_name}
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
                      phx-click="sync_slack"
                      phx-value-id={installation.id}
                      phx-disable-with="Syncing..."
                    >
                      <.icon name="hero-arrow-path" class="h-4 w-4" /> Sync channels
                    </.primary_button>
                    <button
                      type="button"
                      class="inline-flex items-center justify-center rounded-md border border-red-300 px-3 py-1.5 text-xs font-medium text-red-600 transition hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-offset-2 dark:border-red-500/60 dark:text-red-300 dark:hover:bg-red-500/10 dark:focus:ring-offset-slate-900"
                      phx-click="remove_slack_installation"
                      phx-value-id={installation.id}
                      data-confirm="Disconnect {installation.team_name}? This removes access for all channels."
                    >
                      Remove workspace
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
                    No channels discovered yet. Run a sync after completing the Slack authorization.
                  </div>
                  <div :if={total_count > 0} class="divide-y divide-gray-200 dark:divide-slate-700">
                    <%= for channel <- installation.channels || [] do %>
                      <div class="px-4 py-3 flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
                        <div class="space-y-1">
                          <p class="text-sm font-medium text-gray-800 dark:text-white flex items-center gap-2">
                            <span class="text-gray-500 dark:text-slate-300">#</span>
                            {channel.name}
                            <span class={[
                              "inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide",
                              channel.enabled &&
                                "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-200",
                              !channel.enabled &&
                                "bg-gray-100 text-gray-600 dark:bg-slate-700/70 dark:text-slate-300"
                            ]}>
                              {channel_status(channel.enabled)}
                            </span>
                          </p>
                          <p class="text-xs text-gray-500 dark:text-slate-400">
                            Deliver with:
                            <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs text-gray-700 dark:text-slate-200">
                              {channel_reference(installation, channel)}
                            </code>
                          </p>
                          <p class="text-xs text-gray-400 dark:text-slate-500">
                            {format_channel_type(channel)}
                          </p>
                        </div>
                        <div class="flex items-center gap-3">
                          <%= if @can_manage do %>
                            <button
                              type="button"
                              class={[
                                "inline-flex items-center justify-center rounded-md border px-3 py-1.5 text-xs font-medium transition focus:outline-none focus:ring-2 focus:ring-offset-2",
                                channel.enabled &&
                                  "border-gray-300 text-gray-700 hover:bg-gray-50 focus:ring-emerald-500 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-700 dark:focus:ring-emerald-500 dark:focus:ring-offset-slate-900",
                                !channel.enabled &&
                                  "border-emerald-300 text-emerald-700 hover:bg-emerald-50 focus:ring-emerald-500 dark:border-emerald-500/50 dark:text-emerald-200 dark:hover:bg-emerald-500/10 dark:focus:ring-emerald-500 dark:focus:ring-offset-slate-900"
                              ]}
                              phx-click="toggle_slack_channel"
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
  defp status_label(:error), do: "Attention"

  defp reference_prefix(installation), do: "slack_#{installation.reference}"

  defp channel_reference(installation, channel),
    do: "#{reference_prefix(installation)}##{channel.name}"

  defp channel_status(true), do: "Enabled"
  defp channel_status(false), do: "Disabled"

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

  defp format_channel_type(%{channel_type: type, is_private: true}) when type in [nil, ""],
    do: "Private channel"

  defp format_channel_type(%{channel_type: "private_channel"}), do: "Private channel"
  defp format_channel_type(%{channel_type: "public_channel"}), do: "Public channel"
  defp format_channel_type(%{channel_type: "group"}), do: "Private group"
  defp format_channel_type(%{channel_type: "im"}), do: "Direct message"

  defp format_channel_type(%{channel_type: other}) when is_binary(other) do
    other
    |> String.replace("_", " ")
    |> String.downcase()
    |> String.trim()
    |> String.capitalize()
  end

  defp format_channel_type(_), do: "Channel"
end
