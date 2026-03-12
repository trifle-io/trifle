defmodule TrifleApp.Components.DashboardPayload do
  @moduledoc false

  use TrifleApp, :html

  attr :rest, :global

  def payload_button(assigns) do
    ~H"""
    <button
      type="button"
      class="inline-flex h-6 w-6 items-center justify-center rounded-full text-slate-400 transition hover:bg-white/5 hover:text-slate-600 focus:outline-none focus:ring-2 focus:ring-teal-500/40 dark:text-slate-500 dark:hover:bg-slate-900/40 dark:hover:text-slate-300"
      aria-label="Inspect dashboard payload"
      title="Inspect dashboard payload"
      {@rest}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="size-3.5"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M3.75 4.5h16.5M3.75 9h16.5m-16.5 4.5h10.5m-10.5 4.5h10.5"
        />
      </svg>
    </button>
    """
  end

  attr :payload, :string, default: "{}"

  def payload_view(assigns) do
    ~H"""
    <div class="space-y-3">
      <p class="text-xs font-medium uppercase tracking-[0.24em] text-slate-500 dark:text-slate-400">
        Persisted dashboard payload
      </p>
      <div class="rounded-2xl border border-slate-200/80 bg-slate-50 px-4 py-4 shadow-sm dark:border-slate-700 dark:bg-slate-950">
        <pre class="max-h-[70vh] overflow-auto whitespace-pre-wrap break-all font-mono text-[12px] leading-5 text-slate-800 dark:text-slate-100">{@payload}</pre>
      </div>
    </div>
    """
  end

  def dashboard_payload_json(nil), do: "{}"

  def dashboard_payload_json(dashboard) do
    dashboard
    |> Map.get(:payload, Map.get(dashboard, "payload", %{}))
    |> Jason.encode!(pretty: true)
  rescue
    _ ->
      dashboard
      |> Map.get(:payload, Map.get(dashboard, "payload", %{}))
      |> inspect(pretty: true, limit: :infinity)
  end
end
