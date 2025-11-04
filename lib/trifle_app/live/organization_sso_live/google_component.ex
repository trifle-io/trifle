defmodule TrifleApp.OrganizationSSOLive.GoogleComponent do
  use TrifleApp, :live_component

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :sso_info, :map, required: true
  attr :can_manage, :boolean, default: false

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-lg overflow-hidden border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800 shadow-sm"
    >
      <button
        type="button"
        class="group w-full px-4 py-3 flex items-center justify-between gap-4 text-left transition-colors hover:bg-gray-50 dark:hover:bg-slate-700/40"
        phx-click={toggle_panel(@id)}
        aria-controls={"#{@id}-body"}
      >
        <div class="flex w-full items-start justify-between">
          <div class="flex items-start gap-3">
            <div class={status_chip(@status)} aria-hidden="true"></div>
            <div>
              <div class="flex items-center gap-2">
                <span class="text-sm font-semibold text-gray-900 dark:text-white group-hover:text-teal-600 dark:group-hover:text-teal-300">
                  Google Single Sign-On
                </span>
                <span class={status_badge_classes(@status)}>
                  {status_label(@status)}
                </span>
              </div>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Allow members to sign in with Google accounts from approved domains.
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
          :if={!@sso_info.credentials_present?}
          class="rounded-lg border border-amber-300 bg-amber-50/70 px-4 py-4 text-sm text-amber-900 dark:border-amber-400/40 dark:bg-amber-500/10 dark:text-amber-200"
        >
          <p class="font-semibold text-amber-900 dark:text-amber-200">
            Configure Google OAuth credentials to enable sign-in.
          </p>
          <p class="mt-2 leading-relaxed">
            Create an OAuth 2.0 Web application in the Google Cloud Console and set the redirect URI to
            <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs text-amber-900 dark:text-amber-200">{@sso_info.redirect_uri}</code>.
            Provide the client ID and client secret as environment variables (see the deployment guide below).
          </p>
        </div>

        <div class="grid gap-4 lg:grid-cols-2">
          <div class="space-y-3">
            <div>
              <p class="text-sm font-semibold text-gray-900 dark:text-white">Allowed domains</p>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Only Google accounts under these domains can join automatically. Existing members can still sign in even if their domain is not listed.
              </p>
              <div
                :if={Enum.empty?(@sso_info.domains)}
                class="mt-3 rounded-md border border-gray-200 dark:border-slate-700 px-3 py-3 text-sm text-gray-500 dark:text-slate-300"
              >
                No domains configured yet.
              </div>
              <ul
                :if={Enum.any?(@sso_info.domains)}
                class="mt-3 space-y-2 rounded-md border border-gray-200 dark:border-slate-700 px-3 py-3"
              >
                <%= for domain <- @sso_info.domains do %>
                  <li class="flex items-center gap-2 text-sm text-gray-800 dark:text-slate-200">
                    <.icon name="hero-globe-alt-mini" class="h-4 w-4 text-teal-500 dark:text-teal-300" />
                    {domain}
                  </li>
                <% end %>
              </ul>
            </div>
            <div class="text-xs text-gray-500 dark:text-slate-400">
              <p>
                Automatic membership provisioning:
                <span class={[
                  "ml-1 font-medium",
                  if(@sso_info.auto_provision, do: "text-emerald-600 dark:text-emerald-300", else: "text-amber-700 dark:text-amber-200")
                ]}>
                  {@sso_info.auto_provision && "On" || "Off"}
                </span>
              </p>
              <p class="mt-1">
                Provider status:
                <span class={[
                  "ml-1 font-medium",
                  if(@sso_info.enabled, do: "text-emerald-600 dark:text-emerald-300", else: "text-amber-700 dark:text-amber-200")
                ]}>
                  {@sso_info.enabled && "Enabled" || "Disabled"}
                </span>
              </p>
            </div>
          </div>

          <div class="space-y-3">
            <p class="text-sm font-semibold text-gray-900 dark:text-white">Deployment checklist</p>
            <ol class="space-y-2 text-xs text-gray-600 dark:text-slate-300">
              <li>
                1. Go to the
                <a
                  href="https://console.cloud.google.com/apis/credentials"
                  target="_blank"
                  rel="noreferrer noopener"
                  class="underline decoration-teal-500/50 hover:text-teal-600 dark:hover:text-teal-300"
                >
                  Google Cloud Console
                </a>
                and create OAuth client credentials (Web application).
              </li>
              <li>
                2. Add <code class="rounded bg-gray-100 dark:bg-slate-700 px-1 py-0.5 text-xs text-gray-700 dark:text-slate-200">{@sso_info.redirect_uri}</code> as an authorized redirect URI.
              </li>
              <li>
                3. Set the deployment environment variables:
                <div class="mt-2 rounded border border-gray-200 bg-gray-50 dark:border-slate-700 dark:bg-slate-900/40 p-3 font-mono text-[11px] text-gray-700 dark:text-slate-200">
                  GOOGLE_OAUTH_CLIENT_ID=<em>your-client-id</em><br />
                  GOOGLE_OAUTH_CLIENT_SECRET=<em>your-client-secret</em><br />
                  GOOGLE_OAUTH_REDIRECT_URI=<em>optional override</em>
                </div>
              </li>
              <li>
                4. Redeploy and configure the allowed domains below.
              </li>
            </ol>
          </div>
        </div>

        <div class="flex items-center justify-end gap-3">
          <%= if @can_manage do %>
            <.primary_button type="button" phx-click="open_google_sso_modal" class="gap-2">
              <.icon name="hero-cog-6-tooth-mini" class="h-4 w-4" /> Manage Google SSO
            </.primary_button>
          <% else %>
            <span class="text-xs text-gray-500 dark:text-slate-400">
              Only organization admins can manage Google SSO settings.
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_panel(id) do
    Phoenix.LiveView.JS.toggle(
      to: "##{id}-body",
      in: {"transition ease-out duration-150", "opacity-0 h-0", "opacity-100 h-auto"},
      out: {"transition ease-in duration-100", "opacity-100 h-auto", "opacity-0 h-0"}
    )
    |> Phoenix.LiveView.JS.toggle(
      to: "##{id}-chevron",
      in: {"transition ease-out duration-150", "rotate-0", "-rotate-180"},
      out: {"transition ease-in duration-150", "-rotate-180", "rotate-0"}
    )
  end

  defp status_label(:ok), do: "Configured"
  defp status_label(:warning), do: "Attention"
  defp status_label(_), do: "Unavailable"

  defp status_chip(:ok), do: "mt-1 h-2 w-2 rounded-full bg-emerald-500"
  defp status_chip(:warning), do: "mt-1 h-2 w-2 rounded-full bg-amber-400"
  defp status_chip(_), do: "mt-1 h-2 w-2 rounded-full bg-red-500"

  defp status_badge_classes(:ok) do
    "inline-flex items-center rounded-full bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-200 px-2 py-0.5 text-xs font-medium"
  end

  defp status_badge_classes(:warning) do
    "inline-flex items-center rounded-full bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-200 px-2 py-0.5 text-xs font-medium"
  end

  defp status_badge_classes(_status) do
    "inline-flex items-center rounded-full bg-red-100 text-red-700 dark:bg-red-500/20 dark:text-red-200 px-2 py-0.5 text-xs font-medium"
  end
end
