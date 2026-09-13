defmodule TrifleApp.Components.Traces do
  @moduledoc "Independent building blocks for the trace browser."
  use TrifleApp, :html
  alias Trifle.Traces.Reader
  alias TrifleApp.TracesLive.Query
  alias TrifleApp.TracesLive.CopyText
  alias TrifleApp.Components.DashboardWidgets.{ExpandedChart, WidgetView}
  alias TrifleApp.DesignSystem.PathColors
  alias TrifleApp.DesignSystem.TraceStates

  attr :params, :map, required: true
  attr :paths, :list, required: true

  def filters(assigns) do
    ~H"""
    <section aria-label="Trace filters" class="trace-filter-container">
      <form id="trace-filters" phx-submit="apply_filters" class="trace-filter-layout grid gap-5">
        <div class="trace-filter-pair grid min-w-0 gap-x-3 gap-y-5">
          <.labeled_input
            id="trace-filter-path"
            label="Trace path"
            name="path"
            value={@params["path"]}
            list="trace-paths"
            placeholder="All traces"
            class="min-w-0"
            input_class="h-10 text-sm"
          />
          <.labeled_select
            id="trace-filter-state"
            label="State"
            name="state"
            class="w-32 justify-self-end"
            select_class="h-10 text-sm"
          >
            <option
              :for={state <- ["", "running", "success", "warning", "error"]}
              value={state}
              selected={(@params["state"] || "") == state}
            >
              {if state == "", do: "Any state", else: String.capitalize(state)}
            </option>
          </.labeled_select>
        </div>
        <div class="trace-filter-pair grid min-w-0 gap-x-3 gap-y-5">
          <.labeled_input
            id="trace-filter-tags"
            label="Tags (comma-separated)"
            name="tags"
            value={@params["tags"]}
            placeholder="queue:default, scheduled"
            class="min-w-0"
            input_class="h-10 text-sm"
          />
          <.labeled_select
            id="trace-filter-tag-mode"
            label="Match tags"
            name="tag_mode"
            class="w-32 justify-self-end"
            select_class="h-10 text-sm"
          >
            <option value="any" selected={@params["tag_mode"] != "all"}>Any</option>
            <option value="all" selected={@params["tag_mode"] == "all"}>All</option>
          </.labeled_select>
        </div>
        <div class="trace-filter-actions flex flex-wrap items-end justify-between gap-x-3 gap-y-5">
          <.labeled_input
            id="trace-filter-duration"
            label="Min. duration (ms)"
            type="number"
            min="0"
            step="1"
            name="duration_min"
            value={@params["duration_min"]}
            class="w-36 shrink-0"
            input_class="h-10 text-sm"
          />
          <button class="ml-auto h-10 shrink-0 whitespace-nowrap rounded-md bg-teal-600 px-4 py-2 text-sm font-medium text-white hover:bg-teal-700">
            Apply filters
          </button>
        </div>
        <datalist id="trace-paths"><option :for={path <- @paths} value={path} /></datalist>
      </form>
    </section>
    """
  end

  attr :activity, :map, required: true
  attr :path, :string, default: nil
  attr :state, :string, default: nil
  attr :loading, :boolean, required: true
  attr :error, :string, default: nil
  attr :timezone, :string, required: true
  attr :expanded, :boolean, default: false
  attr :presentation, :string, default: "both", values: ~w(both widget expanded)

  def activity(assigns) do
    title =
      "Activity · " <>
        if(assigns.path, do: assigns.path <> " (including descendants)", else: "All traces")

    title = if assigns.state, do: title <> " · " <> String.capitalize(assigns.state), else: title

    widget = %{
      "id" => "trace-activity",
      "type" => "timeseries",
      "title" => title,
      "chart_type" => "bar",
      "stacked" => true,
      "legend" => false,
      "y_label" => "Events",
      "w" => 12,
      "h" => 3,
      "x" => 0,
      "y" => 0
    }

    chart = %{
      id: widget["id"],
      chart_type: "bar",
      stacked: true,
      normalized: false,
      legend: false,
      y_label: "Events",
      secondary_y_label: "Avg. duration (ms)",
      timezone: assigns.timezone,
      series:
        Enum.map(
          assigns.activity.series,
          &Map.put_new(&1, :color, TraceStates.color(Map.get(&1, :state)))
        )
    }

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:chart, if(assigns.loading, do: nil, else: chart))
      |> assign(:dashboard, %{id: "traces", payload: %{"grid" => [widget]}})

    ~H"""
    <section :if={@presentation != "expanded"} aria-label="Trace activity">
      <p
        :if={Enum.any?(@activity.series, &(Map.get(&1, :state) == "unclassified"))}
        class="mb-3 px-1 text-xs text-slate-500 dark:text-slate-400"
      >
        Gray activity has no recognized state counter. Select a state to exclude it.
      </p>
      <p :if={@error} role="status" class="mt-3 text-sm text-amber-700 dark:text-amber-400">
        {@error}
      </p>
      <WidgetView.grid
        grid_dom_id="traces-dashboard-grid"
        dashboard={@dashboard}
        min_rows={3}
        timeseries={if @chart, do: %{"trace-activity" => @chart}, else: %{}}
        loading={@loading}
        hide_on_patch={false}
        widget_export={%{type: :disabled}}
      />
      <p :if={!@loading && !@error && @activity.series == []} class="mt-2 text-sm text-slate-500">
        No recorded activity for this path, state and timeframe.
      </p>
    </section>
    <.app_modal
      :if={@expanded && @presentation != "widget"}
      id="traces-expanded-widget"
      show={true}
      size="full"
      on_cancel={JS.push("close_expanded_widget")}
    >
      <:title>
        <div class="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
          <span class="break-all">{@title}</span>
          <span class="inline-flex items-center rounded-full bg-teal-100/70 dark:bg-teal-900/40 px-3 py-0.5 text-xs font-medium text-teal-700 dark:text-teal-200">
            Timeseries
          </span>
        </div>
      </:title>
      <:body>
        <p class="mb-4 text-xs text-slate-500 dark:text-slate-400">
          Activity counts per time bucket and state, with average duration on the right axis. Toggle a trace path in the legend to hide its states and exclude it from the weighted average. Tags and duration filter only the trace list.
        </p>
        <p :if={@error} role="status" class="mb-4 text-sm text-amber-700 dark:text-amber-400">
          {@error}
        </p>
        <p :if={@loading} role="status" class="mb-4 text-sm text-slate-500 dark:text-slate-400">
          Loading activity…
        </p>
        <ExpandedChart.content id="expanded-widget-trace-activity" title={@title} chart={@chart} />
      </:body>
    </.app_modal>
    """
  end

  attr :traces, :list, required: true
  attr :path_colors, :map, required: true
  attr :params, :map, required: true
  attr :selected, :string, default: nil
  attr :collapsed, :boolean, required: true
  attr :loading, :boolean, required: true
  attr :error, :string, default: nil
  attr :cursor, :string, default: nil

  def list(assigns) do
    ~H"""
    <aside
      id="trace-list"
      aria-label="Trace list"
      class={[
        "w-full min-h-0 min-w-0 shrink-0 overflow-auto",
        @selected &&
          "trace-list-split border-r border-slate-200 dark:border-slate-700 md:w-80 lg:w-96",
        @collapsed && @selected && "hidden",
        !@collapsed && @selected && "hidden md:block"
      ]}
    >
      <div class="border-b border-slate-200 p-4 dark:border-slate-700">
        <form id="trace-reference" phx-submit="open_reference" class="flex items-center gap-2">
          <.labeled_input
            id="trace-reference-input"
            label="Trace reference"
            name="reference"
            aria-label="Trace reference"
            placeholder="Open exact reference…"
            required
            class="min-w-0 flex-1"
            input_class="h-10 text-sm"
          />
          <button class="text-sm font-medium text-teal-600 dark:text-teal-400">Open</button>
        </form>
      </div>
      <p :if={@error} role="status" class="p-4 text-sm text-amber-700 dark:text-amber-400">
        {@error}
      </p>
      <div class="trace-list-rows">
        <.link
          :for={trace <- @traces}
          patch={Query.url(Map.put(@params, "reference", trace.reference))}
          class={[
            "flex items-start gap-3 border-b border-slate-100 px-4 py-3 hover:bg-slate-50 dark:border-slate-800 dark:hover:bg-slate-800",
            @selected == trace.reference && "bg-teal-50 dark:bg-slate-800"
          ]}
          aria-current={if @selected == trace.reference, do: "true", else: "false"}
        >
          <.state_icon state={trace.state} />
          <div class={[
            "trace-row-content grid min-w-0 flex-1 grid-cols-1 items-baseline gap-x-4 gap-y-1",
            !@selected && "md:grid-cols-[minmax(0,1fr)_auto]"
          ]}>
            <div class="trace-row-summary min-w-0">
              <p
                class="min-w-0 text-sm font-medium [overflow-wrap:anywhere]"
                data-trace-path={trace.key}
              >
                {PathColors.html(trace.key, @path_colors, "/")}
              </p>
              <.row_metadata trace={trace} />
            </div>
            <p class="trace-row-timing whitespace-nowrap text-xs tabular-nums text-slate-500 dark:text-slate-400">
              {time(trace.first_at)}
            </p>
          </div>
        </.link>
      </div>
      <p :if={!@loading && !@error && @traces == []} class="p-4 text-sm text-slate-500">
        No traces match. Try a wider timeframe or fewer filters.
      </p>
      <p :if={@loading} role="status" class="p-4 text-sm text-slate-500">Loading traces…</p>
      <button
        :if={@cursor}
        phx-click="load_more"
        disabled={@loading}
        class="w-full p-3 text-sm font-medium text-teal-600 disabled:opacity-50"
      >
        Load more
      </button>
    </aside>
    """
  end

  attr :trace, :map, required: true

  def row_metadata(assigns) do
    counters = Reader.field(assigns.trace, :counters) || %{}
    types = Reader.field(counters, :types) || %{}

    assigns =
      assigns
      |> assign(:entries, Reader.field(assigns.trace, :length) || 0)
      |> assign(:tags, length(Reader.field(assigns.trace, :tags) || []))
      |> assign(:attachments, Reader.field(types, :media) || 0)
      |> assign(:duration, Reader.field(assigns.trace, :duration) || 0)

    ~H"""
    <dl class="trace-row-metadata mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs tabular-nums text-slate-500 dark:text-slate-400">
      <.metadata_item name="entries" label="Entries" icon="sidebar-traces" value={@entries} />
      <.metadata_item name="tags" label="Tags" icon="hero-tag" value={@tags} />
      <.metadata_item
        name="attachments"
        label="Attachments"
        icon="hero-paper-clip"
        value={@attachments}
      />
      <.metadata_item name="duration" label="Duration" icon="hero-bolt" value={"#{@duration} ms"} />
    </dl>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :value, :any, required: true
  attr :class, :string, default: ""

  defp metadata_item(assigns) do
    ~H"""
    <div
      data-trace-metadata={@name}
      title={"#{@label}: #{@value}"}
      class={["inline-flex items-center gap-1 whitespace-nowrap", @class]}
    >
      <dt class="flex">
        <TrifleApp.SidebarIcons.icon name={@icon} class="h-4 w-4 shrink-0" />
        <span class="sr-only">{@label}</span>
      </dt>
      <dd>{@value}</dd>
    </div>
    """
  end

  attr :record, :any, default: nil
  attr :path_colors, :map, required: true
  attr :entries, :list, required: true
  attr :selected, :string, default: nil
  attr :collapsed, :boolean, required: true
  attr :loading, :boolean, required: true
  attr :error, :string, default: nil
  attr :part, :integer, required: true
  attr :source_id, :string, required: true
  attr :previews, :map, required: true
  attr :preview_loading, :boolean, required: true
  attr :preview_error, :string, default: nil
  attr :params, :map, default: %{}
  attr :attachments, :list, default: []
  attr :attachments_open, :boolean, default: false
  attr :attachments_requested, :boolean, default: false
  attr :attachments_loading, :boolean, default: false
  attr :attachments_error, :string, default: nil
  attr :attachments_next_part, :any, default: nil
  attr :show_entry_timestamps, :boolean, default: true

  def detail(assigns) do
    ~H"""
    <section
      :if={@selected}
      id="trace-detail"
      aria-label="Trace detail"
      aria-busy={to_string(@loading)}
      class="relative min-w-0 flex-1"
    >
      <header
        id="trace-detail-header"
        class="trace-detail-header sticky z-20 overflow-auto border-b border-slate-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-900"
      >
        <div
          :if={@loading}
          id="trace-detail-loading"
          class="grid-widget-refresh-indicator"
          role="status"
        >
          <span class="sr-only">
            <%= if @record do %>
              Loading trace content ({@part}/{@record.parts} parts loaded)…
            <% else %>
              Loading trace…
            <% end %>
          </span>
        </div>
        <div class="absolute right-4 top-4 flex items-center gap-1" data-detail-actions>
          <.copy_button
            record={@record}
            entries={@entries}
            part={@part}
            source_id={@source_id}
            reference={@selected}
            loading={@loading}
          />
          <TrifleApp.DesignSystem.IconButton.icon_button
            icon={if @collapsed, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
            size="md"
            label={if @collapsed, do: "Restore split view", else: "Expand detail"}
            phx-click="toggle_list"
            aria-pressed={to_string(@collapsed)}
            aria-controls="trace-list trace-detail"
            class="max-md:hidden"
          />
          <TrifleApp.DesignSystem.IconButton.icon_button
            icon="hero-x-mark"
            size="md"
            label="Close detail"
            phx-click="close_trace"
          />
        </div>
        <div
          :if={!@record}
          class="min-h-[4rem] p-4 pr-24 text-sm text-slate-500 md:pr-32 dark:text-slate-400"
        >
          {if @loading, do: "Loading trace…", else: "Trace detail"}
        </div>
        <%= if @record do %>
          <h2 class="flex min-w-0 items-start gap-2 pr-20 text-base font-semibold md:pr-28">
            <.state_icon state={@record.state} />
            <span class="min-w-0 [overflow-wrap:anywhere]" data-trace-path={@record.key}>
              <.link
                :for={part <- PathColors.parts(@record.key, @path_colors, "/")}
                patch={Query.path_url(@params, Enum.join(part.segments, "/"))}
                title={"Traces under #{Enum.join(part.segments, "/")}"}
                class="rounded-sm hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500"
                style={"color: #{part.color} !important"}
                phx-no-format
              >{part.label}</.link>
            </span>
          </h2>
          <div class="mt-1 flex items-center gap-1 pr-20 text-xs text-slate-500 md:pr-28 dark:text-slate-400">
            <span class="min-w-0 [overflow-wrap:anywhere]">{@record.reference}</span>
            <.copy_control
              id={"trace-reference-copy-#{@source_id}-#{@record.reference}"}
              text={@record.reference}
              kind="reference"
              size="sm"
            />
          </div>
          <.arguments id={"trace-arguments-#{@source_id}-#{@record.reference}"} meta={@record.meta} />
          <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs tabular-nums text-slate-500 dark:text-slate-400">
            <span class="inline-flex flex-wrap items-center gap-x-2 gap-y-1" data-detail-timing>
              <TrifleApp.SidebarIcons.icon name="hero-bolt" class="h-4 w-4 shrink-0" />
              <span class="whitespace-nowrap" title="Started">
                <span class="sr-only">Started:</span> {time(@record.first_at)}
              </span>
              <span aria-hidden="true">→</span>
              <span class="whitespace-nowrap" title="Duration">
                <span class="sr-only">Duration:</span> {@record.duration} ms
              </span>
              <span aria-hidden="true">→</span>
              <span class="whitespace-nowrap" title="Last update">
                <span class="sr-only">Last update:</span> {time(@record.last_at)}
              </span>
            </span>
          </div>
          <.entry_counts record={@record} />
          <details
            :if={@record.tags not in [nil, []]}
            id={"trace-tags-#{@source_id}-#{@record.reference}"}
            class="mt-3 text-sm"
            data-trace-tags
          >
            <summary class="cursor-pointer text-slate-500 dark:text-slate-400">
              <span class="inline-flex items-center gap-1 align-middle">
                <TrifleApp.SidebarIcons.icon name="hero-tag" class="h-4 w-4 shrink-0" />
                <span>Tags</span>
                <span class="tabular-nums">({length(@record.tags)})</span>
              </span>
            </summary>
            <div
              class="mt-2 flex max-h-72 flex-wrap gap-2 overflow-y-auto p-1"
              aria-label="Trace tags"
            >
              <.link
                :for={tag <- @record.tags}
                patch={Query.tag_url(@params, tag)}
                title={"Filter traces by tag: #{tag}"}
                data-trace-tag={tag}
                class="inline-flex min-w-0 max-w-full items-start gap-1 rounded-md bg-slate-100 px-2 py-1 text-xs text-slate-600 hover:bg-slate-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700"
              >
                <TrifleApp.SidebarIcons.icon name="hero-tag" class="h-4 w-4 shrink-0" />
                <span class="min-w-0 [overflow-wrap:anywhere]">{tag}</span>
              </.link>
            </div>
          </details>
          <.attachments_section
            record={@record}
            source_id={@source_id}
            attachments={@attachments}
            open={@attachments_open}
            requested={@attachments_requested}
            loading={@attachments_loading}
            error={@attachments_error}
            next_part={@attachments_next_part}
          />
          <details id={"trace-metadata-#{@record.reference}"} class="mt-3 text-sm">
            <summary class="cursor-pointer text-slate-500 dark:text-slate-400">
              <span class="inline-flex items-center gap-1 align-middle">
                <TrifleApp.SidebarIcons.icon name="trace-metadata" class="h-4 w-4 shrink-0" />
                <span>Metadata</span>
              </span>
            </summary>
            <pre class="mt-2 max-h-72 overflow-auto whitespace-pre-wrap break-all text-xs">{json(%{meta: @record.meta, context: @record.context, counters: @record.counters})}</pre>
          </details>
          <p :if={to_string(@record.state) == "running"} class="mt-3 text-xs text-slate-500">
            Running · stored content only. Refresh manually for updates.
          </p>
        <% end %>
      </header>
      <div :if={@error} role="status" class="p-4 text-sm text-amber-700 dark:text-amber-400">
        {@error} <button phx-click="retry_detail" class="ml-2 underline">Retry</button>
      </div>
      <div class="trace-entry-body pb-4">
        <.entry_list
          entries={@entries}
          total={if @record, do: @record.length || 0, else: 0}
          reference={@selected}
          source_id={@source_id}
          previews={@previews}
          preview_loading={@preview_loading}
          show_timestamps={@show_entry_timestamps}
        />
        <p :if={@preview_loading} role="status" class="px-4 py-3 text-sm text-slate-500">
          Loading attachment…
        </p>
        <p
          :if={@preview_error}
          role="status"
          class="px-4 py-3 text-sm text-amber-700 dark:text-amber-400"
        >
          {@preview_error}
        </p>
        <p :if={@record && @record.parts == 0 && !@loading} class="px-4 py-3 text-sm text-slate-500">
          No stored entries yet.
        </p>
        <button
          :if={@record && @part < @record.parts && !@error && !@loading}
          phx-click="load_part"
          disabled={@loading}
          class="px-4 py-3 text-sm text-teal-600 disabled:opacity-50"
        >
          Load next part ({@part}/{@record.parts} loaded)
        </button>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :meta, :any, default: nil

  def arguments(assigns) do
    arguments = assigns.meta
    compact = Jason.encode!(arguments)
    {preview, remaining} = String.split_at(compact, 240)

    assigns =
      assigns
      |> assign(:arguments, arguments)
      |> assign(:preview, if(remaining == "", do: preview, else: preview <> "…"))
      |> assign(:truncated, remaining != "")

    ~H"""
    <section
      :if={@arguments not in [nil, [], %{}]}
      id={@id}
      aria-label="Arguments"
      data-trace-arguments
      class="mt-2 min-w-0 text-xs text-slate-700 dark:text-slate-200"
    >
      <details :if={@truncated} id={@id <> "-disclosure"} class="group/arguments">
        <summary class="flex cursor-pointer flex-wrap items-baseline gap-x-2 gap-y-1 rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-teal-500 [&::-webkit-details-marker]:hidden">
          <code
            data-arguments-preview
            class="min-w-0 whitespace-pre-wrap [overflow-wrap:anywhere] group-open/arguments:hidden"
            phx-no-format
          >{@preview}</code>
          <span
            data-arguments-expand
            class="whitespace-nowrap text-teal-600 hover:underline group-open/arguments:hidden dark:text-teal-400"
          >
            Expand all
          </span>
          <span class="hidden text-teal-600 hover:underline group-open/arguments:inline dark:text-teal-400">
            Collapse
          </span>
        </summary>
        <pre data-arguments-full class="mt-1 whitespace-pre-wrap [overflow-wrap:anywhere]">{json(@arguments)}</pre>
      </details>
      <pre
        :if={!@truncated}
        data-arguments-preview
        class="whitespace-pre-wrap [overflow-wrap:anywhere]"
      >{@preview}</pre>
    </section>
    """
  end

  attr :entries, :list, required: true
  attr :record, :any, default: nil
  attr :part, :integer, required: true
  attr :source_id, :string, required: true
  attr :reference, :string, required: true
  attr :loading, :boolean, default: false

  def copy_button(assigns) do
    ~H"""
    <.copy_control
      id={"trace-copy-#{@source_id}-#{@reference}"}
      text={if @record, do: CopyText.format(@record, @entries, @part)}
      ready={!is_nil(@record) && !@loading}
    />
    """
  end

  attr :id, :string, required: true
  attr :text, :string, default: nil
  attr :ready, :boolean, default: true
  attr :kind, :string, default: "trace", values: ~w(trace reference)
  attr :size, :string, default: "md", values: ~w(sm md)

  defp copy_control(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="TraceCopy"
      class="relative inline-flex shrink-0"
      data-copy-kind={@kind}
      data-copy-ready={to_string(@ready)}
    >
      <TrifleApp.DesignSystem.IconButton.icon_button
        icon="hero-clipboard-document"
        size={@size}
        label={if @kind == "reference", do: "Copy trace reference", else: "Copy loaded trace text"}
        data-copy-button
        disabled={!@ready}
        class="disabled:opacity-50"
      />
      <span
        data-copy-success
        class="pointer-events-none absolute inset-0 hidden items-center justify-center"
        aria-hidden="true"
      >
        <TrifleApp.SidebarIcons.icon
          name="hero-clipboard-document-check"
          class={[
            if(@size == "sm", do: "h-4 w-4", else: "h-6 w-6"),
            "text-teal-500 dark:text-teal-400"
          ]}
        />
      </span>
      <span
        data-copy-status
        role="status"
        aria-live="polite"
        class="sr-only"
        data-copy-error-class="absolute right-0 top-full z-10 mt-1 w-56 rounded bg-white p-2 text-xs text-red-600 shadow ring-1 ring-slate-200 dark:bg-slate-800 dark:text-red-400 dark:ring-slate-700"
      >
      </span>
      <pre :if={!is_nil(@text)} data-copy-text class="hidden" aria-hidden="true">{@text}</pre>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :total, :integer, default: 0
  attr :reference, :string, required: true
  attr :source_id, :string, required: true
  attr :previews, :map, default: %{}
  attr :preview_loading, :boolean, default: false
  attr :show_timestamps, :boolean, default: true

  def entry_list(assigns) do
    # Number persisted entries, not wrapped display lines, across all loaded parts.
    line_width = max(2, String.length(to_string(max(assigns.total, length(assigns.entries)))))
    assigns = assign(assigns, :line_width, line_width)

    ~H"""
    <ol
      class="trace-entries font-mono text-xs leading-5"
      aria-label="Trace entries"
      role="list"
      style={"--trace-line-width: #{@line_width}ch;"}
      data-show-timestamps={to_string(@show_timestamps)}
    >
      <li
        :for={{item, number} <- Enum.with_index(@entries, 1)}
        id={"trace-entry-#{item.part}-#{item.row}"}
        data-entry-state={Reader.field(item.entry, :state)}
        class="trace-entry grid items-start gap-x-3 border-b border-slate-100 px-4 py-0.5 dark:border-slate-800"
      >
        <span
          class="trace-entry-number select-none text-right tabular-nums text-slate-400 dark:text-slate-500"
          aria-hidden="true"
        >
          {number}
        </span>
        <div
          class={["trace-entry-message min-w-0", entry_color(Reader.field(item.entry, :state))]}
          style={"--trace-entry-indent: #{indent(item.entry)}rem;"}
        >
          <span class="sr-only">{Reader.field(item.entry, :state)}:</span>
          <%= if to_string(Reader.field(item.entry, :type)) == "media" do %>
            <%= if media_type = Trifle.Traces.Media.type(Reader.field(item.entry, :message)) do %>
              <.inline_media
                item={item}
                kind={elem(media_type, 0)}
                reference={@reference}
                source_id={@source_id}
              />
            <% else %>
              <div class="flex flex-wrap gap-x-3">
                <span class="min-w-0 [overflow-wrap:anywhere]">
                  {Reader.field(item.entry, :message)}
                </span>
                <.attachment_size bytes={Reader.field(item.entry, :size)} />
                <button
                  phx-click="preview"
                  phx-value-part={item.part}
                  phx-value-row={item.row}
                  disabled={@preview_loading}
                  class="text-teal-600 dark:text-teal-400"
                >
                  Read text
                </button>
                <a
                  href={
                    ~p"/traces/attachment?#{%{source_id: @source_id, reference: @reference, part: item.part, row: item.row}}"
                  }
                  class="text-teal-600 dark:text-teal-400"
                >
                  Download
                </a>
              </div>
              <%= if preview = @previews[{item.part, item.row}] do %>
                <pre :if={preview.text} class="mt-2 whitespace-pre-wrap [overflow-wrap:anywhere]">{preview.text}</pre>
                <p :if={preview.truncated} class="mt-2 font-sans text-slate-500 dark:text-slate-400">
                  Preview truncated. Download for the full text.
                </p>
                <p :if={!preview.text} class="mt-2 font-sans text-slate-500 dark:text-slate-400">
                  No text preview available. Download this attachment to open it.
                </p>
              <% end %>
            <% end %>
          <% else %>
            <pre class={[
              "whitespace-pre-wrap [overflow-wrap:anywhere]",
              to_string(Reader.field(item.entry, :type)) == "head" && "font-semibold"
            ]}>{text(Reader.field(item.entry, :message))}</pre>
          <% end %>
        </div>
        <time
          :if={@show_timestamps}
          class="trace-entry-timestamp select-none max-w-full text-right font-sans tabular-nums text-slate-400 [overflow-wrap:anywhere] dark:text-slate-500"
          datetime={iso_time(Reader.field(item.entry, :at))}
        >
          {time(Reader.field(item.entry, :at))}
        </time>
      </li>
    </ol>
    """
  end

  attr :item, :map, required: true
  attr :kind, :atom, required: true
  attr :reference, :string, required: true
  attr :source_id, :string, required: true

  def inline_media(assigns) do
    assigns =
      assigns
      |> assign(:name, Reader.field(assigns.item.entry, :message))
      |> assign(:params, %{
        source_id: assigns.source_id,
        reference: assigns.reference,
        part: assigns.item.part,
        row: assigns.item.row
      })
      |> assign(
        :media_id,
        "trace-media-#{assigns.source_id}-#{assigns.reference}-#{assigns.item.part}-#{assigns.item.row}"
      )

    ~H"""
    <div
      id={@media_id}
      phx-hook="TraceMedia"
      phx-update="ignore"
      data-media-kind={@kind}
      data-media-url={~p"/traces/attachment?#{Map.put(@params, :inline, true)}"}
    >
      <div class="flex flex-wrap items-baseline gap-x-3">
        <span class="min-w-0 [overflow-wrap:anywhere]">{@name}</span>
        <.attachment_size bytes={Reader.field(@item.entry, :size)} />
        <button
          type="button"
          data-media-toggle
          aria-expanded="true"
          aria-controls={@media_id <> "-preview"}
          class="text-teal-600 hover:underline focus-visible:underline dark:text-teal-400"
        >
          {if @kind == :image, do: "Hide image", else: "Hide video"}
        </button>
        <a
          href={~p"/traces/attachment?#{@params}"}
          class="text-teal-600 hover:underline dark:text-teal-400"
        >
          Download
        </a>
      </div>
      <p
        data-media-status
        role="status"
        aria-live="polite"
        class="font-sans text-slate-500 dark:text-slate-400"
      >
      </p>
      <div id={@media_id <> "-preview"} data-media-preview class="py-2">
        <img
          :if={@kind == :image}
          data-media-element
          src={~p"/traces/attachment?#{Map.put(@params, :inline, true)}"}
          alt={@name}
          loading="lazy"
          decoding="async"
          class="block h-auto max-h-[32rem] max-w-full object-contain object-left"
        />
        <video
          :if={@kind == :video}
          data-media-element
          src={~p"/traces/attachment?#{Map.put(@params, :inline, true)}"}
          controls
          playsinline
          preload="metadata"
          aria-label={@name}
          class="block max-h-[32rem] w-full"
        >
          Your browser does not support inline video. Use Download to open this attachment.
        </video>
      </div>
    </div>
    """
  end

  attr :record, :map, required: true

  def entry_counts(assigns) do
    ~H"""
    <dl
      class="mt-3 flex flex-wrap items-center gap-x-3 gap-y-2 text-xs tabular-nums text-slate-500 dark:text-slate-400"
      data-entry-counts
    >
      <.metadata_item
        :for={state <- [:success, :warning, :error, :debug]}
        name={"entries-#{state}"}
        label={"#{String.capitalize(to_string(state))} entries"}
        icon="sidebar-traces"
        value={counter(@record, :states, state)}
        class={
          if state == :success,
            do: "text-slate-500 dark:text-slate-400",
            else: state_color(state)
        }
      />
    </dl>
    """
  end

  attr :record, :map, required: true
  attr :source_id, :string, required: true
  attr :attachments, :list, required: true
  attr :open, :boolean, default: false
  attr :requested, :boolean, required: true
  attr :loading, :boolean, required: true
  attr :error, :string, default: nil
  attr :next_part, :any, default: nil

  def attachments_section(assigns) do
    ~H"""
    <details
      id={"trace-attachments-#{@record.reference}"}
      open={@open}
      class="mt-3 text-sm"
      data-trace-attachments
    >
      <summary
        phx-click="toggle_attachments"
        class="cursor-pointer text-slate-500 dark:text-slate-400"
      >
        <span class="inline-flex items-center gap-1 align-middle">
          <TrifleApp.SidebarIcons.icon name="hero-paper-clip" class="h-4 w-4 shrink-0" />
          <span>Attachments</span>
          <span class="tabular-nums">({counter(@record, :types, :media)})</span>
        </span>
      </summary>
      <ul :if={@attachments != []} class="mt-2 space-y-2">
        <li
          :for={attachment <- @attachments}
          class="flex flex-wrap items-start gap-x-2 gap-y-1 text-xs"
        >
          <a
            href={
              ~p"/traces/attachment?#{%{source_id: @source_id, reference: @record.reference, part: attachment.part, row: attachment.row}}"
            }
            class="inline-flex max-w-full items-start gap-2 text-xs text-teal-600 hover:underline dark:text-teal-400"
            title={"Download #{attachment.name}"}
          >
            <TrifleApp.SidebarIcons.icon name="hero-paper-clip" class="h-4 w-4 shrink-0" />
            <span class="min-w-0 [overflow-wrap:anywhere]">{attachment.name}</span>
          </a>
          <.attachment_size bytes={Reader.field(attachment, :size)} />
        </li>
      </ul>
      <p :if={@loading} role="status" class="mt-2 text-xs text-slate-500">Loading attachments…</p>
      <p :if={@error} role="status" class="mt-2 text-xs text-amber-600 dark:text-amber-400">
        {@error} <button phx-click="retry_attachments" class="ml-1 underline">Retry</button>
      </p>
      <p
        :if={@requested && !@loading && !@error && @attachments == []}
        class="mt-2 text-xs text-slate-500"
      >
        {if @next_part,
          do: "No attachments in the parts scanned so far.",
          else: "No stored attachments."}
      </p>
      <button
        :if={@next_part && !@error}
        phx-click="more_attachments"
        disabled={@loading}
        class="mt-2 text-xs text-teal-600 disabled:opacity-50 dark:text-teal-400"
      >
        Load more attachments
      </button>
    </details>
    """
  end

  attr :bytes, :any, default: nil

  def attachment_size(assigns) do
    bytes = if is_integer(assigns.bytes) and assigns.bytes >= 0, do: assigns.bytes

    assigns =
      assigns
      |> assign(:bytes, bytes)
      |> assign(:label, format_attachment_size(bytes))

    ~H"""
    <span
      data-attachment-size
      data-size-bytes={@bytes}
      title={if is_nil(@bytes), do: "Attachment size was not recorded", else: "#{@bytes} bytes"}
      aria-label={"Attachment size: #{@label}"}
      class="shrink-0 whitespace-nowrap font-sans tabular-nums text-slate-500 dark:text-slate-400"
    >
      {@label}
    </span>
    """
  end

  defp format_attachment_size(nil), do: "Size unknown"

  defp format_attachment_size(bytes) do
    units = [
      {1_099_511_627_776, "TiB"},
      {1_073_741_824, "GiB"},
      {1_048_576, "MiB"},
      {1_024, "KiB"}
    ]

    case Enum.find(units, fn {factor, _unit} -> bytes >= factor end) do
      nil ->
        "#{bytes} B"

      {factor, unit} ->
        value =
          if rem(bytes, factor) == 0, do: div(bytes, factor), else: Float.round(bytes / factor, 1)

        "#{value} #{unit}"
    end
  end

  defp counter(record, group, key) do
    counters = Reader.field(record, :counters) || %{}
    values = Reader.field(counters, group) || %{}
    Reader.field(values, key) || 0
  end

  attr :state, :any, required: true

  def state_icon(assigns) do
    assigns =
      assigns
      |> assign(
        :label,
        if(to_string(assigns.state) == "",
          do: "Unknown",
          else: String.capitalize(to_string(assigns.state))
        )
      )
      |> assign(:icon, state_icon_name(assigns.state))

    ~H"""
    <span role="img" aria-label={@label} title={@label} data-trace-state={@state} class="shrink-0">
      <TrifleApp.SidebarIcons.icon name={@icon} class={["h-6 w-6", state_color(@state)]} />
    </span>
    """
  end

  defp state_icon_name(state) do
    case to_string(state) do
      "success" -> "hero-check-circle"
      "debug" -> "hero-code-bracket"
      "warning" -> "hero-question-mark-circle"
      state when state in ["error", "running"] -> "hero-exclamation-circle"
      _ -> "hero-question-mark-circle"
    end
  end

  defp state_color(state) do
    case to_string(state) do
      "error" -> "text-red-600 dark:text-red-400"
      "warning" -> "text-amber-500 dark:text-amber-400"
      "success" -> "text-teal-500 dark:text-teal-400"
      "running" -> "text-blue-600 dark:text-blue-400"
      "debug" -> "text-violet-500 dark:text-violet-400"
      _ -> "text-slate-500 dark:text-slate-400"
    end
  end

  defp entry_color(state) do
    case to_string(state) do
      "warning" -> "text-amber-700 dark:text-amber-400"
      "error" -> "text-red-600 dark:text-red-400"
      "debug" -> "text-violet-600 dark:text-violet-400"
      _ -> "text-slate-700 dark:text-slate-200"
    end
  end

  defp iso_time(%DateTime{} = date), do: DateTime.to_iso8601(date)

  defp iso_time(value) when is_integer(value) do
    case DateTime.from_unix(value, :second) do
      {:ok, date} -> iso_time(date)
      _ -> nil
    end
  end

  defp iso_time(_), do: nil

  defp time(nil), do: "—"
  defp time(%DateTime{} = date), do: Calendar.strftime(date, "%Y-%m-%d %H:%M:%S %Z")

  defp time(value) when is_integer(value) do
    # Ruby and Elixir trace payload entries store Unix seconds, unlike charts.
    case DateTime.from_unix(value, :second) do
      {:ok, date} -> time(date)
      _ -> "—"
    end
  end

  defp time(value), do: text(value)
  defp text(value) when is_binary(value), do: value
  defp text(value), do: inspect(value, pretty: true)
  defp json(value), do: Jason.encode!(value, pretty: true)

  defp indent(entry) do
    case Reader.field(entry, :level) do
      n when is_integer(n) -> min(max(n, 0), 12)
      _ -> 0
    end
  end
end
