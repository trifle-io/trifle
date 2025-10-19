defmodule TrifleApp.OrganizationDeliveryLive.EmailComponent do
  use TrifleApp, :live_component

  attr :id, :string, required: true
  attr :status, :atom, required: true
  attr :email_info, :map, required: true

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
                  Email
                </span>
                <span class={[
                  "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium",
                  badge_class(@status)
                ]}>
                  {status_label(@status)}
                </span>
              </div>
              <p class="mt-1 text-xs text-gray-500 dark:text-slate-400">
                Manage outbound email delivery powered by Swoosh.
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
          :if={@status == :ok}
          class="rounded-lg border border-emerald-200 bg-emerald-50/70 px-4 py-3 text-sm text-emerald-800 dark:border-emerald-500/40 dark:bg-emerald-500/10 dark:text-emerald-200"
        >
          <p class="font-medium">
            Email delivery is active via {@email_info.adapter_label ||
              "your configured Swoosh adapter"}.
          </p>
          <p class="mt-2 leading-relaxed">
            Reference recipients anywhere in Trifle using <code class="rounded bg-white/80 dark:bg-slate-700/80 px-1 py-0.5 text-xs text-emerald-700 dark:text-emerald-200">email#you@example.com</code>.
            Messages will be queued through the configured Swoosh adapter and delivered through your infrastructure.
          </p>
        </div>

        <div
          :if={@status != :ok}
          class="rounded-lg border border-amber-200 bg-amber-50/80 px-4 py-3 text-sm text-amber-900 dark:border-amber-400/40 dark:bg-amber-500/10 dark:text-amber-200"
        >
          <p class="font-medium">
            Email delivery is currently using the local mailbox adapter.
          </p>
          <p class="mt-2 leading-relaxed">
            Update your Helm values to point Trifle at a real mail provider. The chart exposes Swoosh adapters through
            <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs text-amber-800 dark:text-amber-200">
              app.mailer.*
            </code>
            settings.
          </p>
          <ol class="mt-3 list-decimal space-y-2 pl-5 text-sm">
            <li>
              Set
              <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">
                app.mailer.adapter
              </code>
              to <code>smtp</code>, <code>postmark</code>, <code>sendgrid</code>, <code>mailgun</code>, or <code>sendinblue</code>.
            </li>
            <li>
              Populate provider credentials under
              <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs">
                app.mailer.*
              </code>
              (see <code>EMAILS.md</code>
              for provider-specific keys).
            </li>
            <li>
              Redeploy the chart so runtime picks up the new environment variables and restarts the app.
            </li>
          </ol>
          <p class="mt-3 leading-relaxed">
            Once complete you can reference real recipients using <code class="rounded bg-white/70 dark:bg-slate-800/80 px-1 py-0.5 text-xs text-amber-800 dark:text-amber-200">email#team@example.com</code>.
          </p>
        </div>

        <div class="rounded-lg border border-gray-200 dark:border-slate-700 px-4 py-3 text-xs text-gray-600 dark:text-slate-300">
          <p class="font-semibold text-gray-700 dark:text-slate-200">Operational checklist</p>
          <ul class="mt-2 space-y-1 list-disc pl-4">
            <li>
              Verify SPF/DKIM with your provider to avoid spam folders.
            </li>
            <li>
              In staging environments stick to <code>local</code>
              so messages land in <code>/dev/mailbox</code>.
            </li>
            <li>
              Store secrets in the Helm release, never directly in <code>config/*.exs</code>.
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_panel(id) do
    JS.toggle(to: "##{id}-body")
    |> JS.toggle_class("rotate-180", to: "##{id}-chevron")
  end

  defp badge_class(:ok),
    do: "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/10 dark:text-emerald-300"

  defp badge_class(:warning),
    do: "bg-amber-100 text-amber-700 dark:bg-amber-500/10 dark:text-amber-200"

  defp badge_class(:error),
    do: "bg-rose-100 text-rose-700 dark:bg-rose-500/10 dark:text-rose-200"

  defp status_label(:ok), do: "Active"
  defp status_label(:warning), do: "Needs configuration"
  defp status_label(:error), do: "Attention"

  defp chip_class(:ok),
    do: "flex-none h-10 w-1.5 rounded bg-emerald-500/90 dark:bg-emerald-400/80"

  defp chip_class(:warning),
    do: "flex-none h-10 w-1.5 rounded bg-amber-500/80 dark:bg-amber-400/70"

  defp chip_class(:error),
    do: "flex-none h-10 w-1.5 rounded bg-rose-500/80 dark:bg-rose-400/70"
end
