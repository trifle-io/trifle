defmodule TrifleApp.Components.TraceOverview do
  use TrifleApp, :html
  alias TrifleApp.TracesLive.Query
  alias TrifleApp.DesignSystem.{ChartColors, PathColors, TraceStates}

  attr :overview, :map, required: true
  attr :params, :map, required: true
  attr :path_colors, :map, required: true
  attr :loading, :boolean, default: false
  attr :error, :any, default: nil
  attr :timezone, :string, required: true
  attr :state, :any, default: nil

  def content(assigns) do
    ~H"""
    <section
      id="trace-overview"
      phx-hook="TraceOverviewPreferences"
      data-overview-columns={@overview.columns}
      data-overview-rows={@overview.row_count}
      aria-label="Overview"
      class="relative shrink-0 rounded-lg border border-slate-200 bg-white dark:border-slate-700 dark:bg-slate-900"
    >
      <div
        :if={@loading}
        class="grid-widget-refresh-indicator"
        data-role="widget-refresh-indicator"
        role="status"
        aria-label="Refreshing overview"
      >
      </div>
      <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-4 py-3 dark:border-slate-700">
        <button
          type="button"
          phx-click="toggle_overview"
          aria-expanded={to_string(!@overview.collapsed)}
          aria-controls="job-overview-body"
          class="flex items-center gap-2 text-sm font-semibold"
        >
          <span aria-hidden="true">{if @overview.collapsed, do: "▸", else: "▾"}</span>
          Overview
          <span class="inline-flex min-w-6 items-center justify-center rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium tabular-nums text-slate-600 dark:bg-slate-800 dark:text-slate-300">
            {format(@overview.total)}
          </span>
        </button>
        <form
          :if={!@overview.collapsed}
          phx-change="overview_controls"
          class="flex flex-wrap items-center gap-2 text-xs"
        >
          <label>
            Sort
            <select name="sort" class="job-overview-select">
              <option
                :for={
                  {label, value} <- [
                    {"Traces", "count"},
                    {"Path", "name"},
                    {"Success rate", "success"},
                    {"Avg duration", "duration"},
                    {"Avg lines", "lines"}
                  ]
                }
                value={value}
                selected={@overview.sort == value}
              >
                {label}
              </option>
            </select>
          </label>
          <.button_group size="sm" labels="hidden">
            <:button
              phx-click="toggle_overview_direction"
              label={if @overview.direction == "asc", do: "Sort descending", else: "Sort ascending"}
              tooltip={
                if @overview.direction == "asc",
                  do: "Ascending · Sort descending",
                  else: "Descending · Sort ascending"
              }
            >
              <.row_control_icon action={
                if @overview.direction == "asc", do: "ascending", else: "descending"
              } />
            </:button>
          </.button_group>
          <div class="flex items-center gap-2" aria-label="Traces per page">
            <.button_group size="sm" labels="hidden">
              <:button
                :for={{label, delta} <- [{"Fewer rows", -1}, {"More rows", 1}]}
                phx-click="overview_rows"
                values={%{"delta" => delta}}
                label={label}
                disabled={
                  if delta == -1, do: @overview.row_count <= 1, else: @overview.row_count >= 100
                }
                tooltip={"#{label} · #{@overview.size} traces per page"}
              >
                <.row_control_icon action={if delta == 1, do: "more", else: "fewer"} />
              </:button>
            </.button_group>
          </div>
          <nav
            :if={@overview.total > 0}
            aria-label="Overview pagination"
            class="ml-2 flex items-center gap-3 border-l border-slate-200 pl-4 dark:border-slate-700"
          >
            <span class="whitespace-nowrap tabular-nums text-slate-500 dark:text-slate-400">
              Page {@overview.page} of {@overview.pages}
            </span>
            <.button_group size="sm" labels="hidden">
              <:button
                phx-click="overview_page"
                values={%{"page" => @overview.page - 1}}
                disabled={@loading || @overview.page <= 1}
                label="Previous page"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M15.75 19.5 8.25 12l7.5-7.5"
                  />
                </svg>
              </:button>
              <:button
                phx-click="overview_page"
                values={%{"page" => @overview.page + 1}}
                disabled={@loading || @overview.page >= @overview.pages}
                label="Next page"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="h-4 w-4"
                  aria-hidden="true"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                </svg>
              </:button>
            </.button_group>
          </nav>
        </form>
      </div>
      <div :if={!@overview.collapsed} id="job-overview-body" aria-busy={to_string(@loading)}>
        <p :if={@loading && @overview.rows == []} class="p-6 text-sm text-slate-500">
          Loading trace activity…
        </p>
        <p :if={@error} role="alert" class="p-6 text-sm text-red-600">{@error}</p>
        <p :if={!@loading && !@error && @overview.rows == []} class="p-6 text-sm text-slate-500">
          No traces match this path, state and timeframe.
        </p>
        <div id="traces-overview-grid" class="job-overview-grid">
          <article :for={row <- @overview.rows} id={widget_id(row.path)} class="job-overview-row">
            <.widget
              row={row}
              params={@params}
              path_colors={@path_colors}
              timezone={@timezone}
              state={@state}
            />
          </article>
        </div>
      </div>
    </section>
    """
  end

  attr :action, :string, required: true, values: ~w(ascending descending more fewer)

  defp row_control_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      stroke-linecap="round"
      stroke-linejoin="round"
      class="h-5 w-5"
      aria-hidden="true"
    >
      <path d="M3 6h10M3 12h7M3 18h4" />
      <path
        stroke-width="1.75"
        d={
          case @action do
            "ascending" -> "M18 19V5m-3 3 3-3 3 3"
            "descending" -> "M18 5v14m-3-3 3 3 3-3"
            "more" -> "M15 18h6m-3-3v6"
            "fewer" -> "M15 18h6"
          end
        }
      />
    </svg>
    """
  end

  def widget_id(path), do: "trace-overview-" <> Base.url_encode64(path, padding: false)

  attr :row, :map, required: true
  attr :timezone, :string, required: true
  attr :path_colors, :map, required: true

  def expanded(assigns) do
    series = Enum.map(assigns.row.series, &Map.put(&1, :color, TraceStates.color(&1.state)))

    measurements = [
      %{
        name: "Average duration",
        chart_type: "line",
        y_axis: "secondary",
        unit: "ms",
        color: ChartColors.color_at(3),
        data: Enum.map(assigns.row.points, &[&1.at, &1.duration])
      }
    ]

    chart = %{
      presentation: "trace_overview",
      chart_type: "bar",
      stacked: true,
      legend: true,
      timezone: assigns.timezone,
      y_label: "Traces",
      secondary_y_label: "Duration (ms)",
      series: series ++ Enum.map(measurements, &Map.put(&1, :stacked, false)),
      points: assigns.row.points,
      states: Enum.map(assigns.row.state_distribution, & &1.state)
    }

    assigns = assign(assigns, :chart, chart)

    ~H"""
    <.app_modal
      id="traces-overview-expanded-widget"
      show={true}
      size="full"
      on_cancel={JS.push("close_expanded_widget")}
    >
      <:title><span class="break-all">{PathColors.html(@row.path, @path_colors, "/")}</span></:title>
      <:body>
        <TrifleApp.Components.DashboardWidgets.ExpandedChart.content
          id={"expanded-" <> widget_id(@row.path)}
          title={@row.path}
          type="trace_overview"
          chart={@chart}
        />
      </:body>
    </.app_modal>
    """
  end

  attr :row, :map, required: true
  attr :params, :map, required: true
  attr :path_colors, :map, required: true
  attr :timezone, :string, required: true
  attr :state, :any, default: nil

  def widget(assigns) do
    ~H"""
    <div class="trace-overview-widget" data-trace-overview-widget>
      <div class="job-overview-header">
        <div class="job-overview-heading">
          <.status_indicator row={@row} />
          <.link
            patch={Query.path_url(@params, @row.path)}
            class="job-overview-title trace-path-label text-base font-semibold hover:underline underline-offset-2"
            data-trace-path={@row.path}
          >
            {PathColors.html(@row.path, @path_colors, "/", wrap: true)}
          </.link>
        </div>
        <div class="job-overview-header-actions">
          <div
            class="job-overview-counter"
            title={"#{format(@row.count)} traces#{if @state not in [nil, ""], do: " · #{@state}"}"}
          >
            <strong class="job-overview-stat tabular-nums font-semibold text-slate-800 dark:text-slate-200">
              {format(@row.count)}
            </strong>
            <span class="text-xs text-slate-500 dark:text-slate-400">
              traces{if @state not in [nil, ""], do: " · #{@state}"}
            </span>
          </div>
          <TrifleApp.DesignSystem.IconButton.icon_button
            icon="hero-arrows-pointing-out"
            label="Expand trace overview"
            class="grid-widget-expand"
            data-widget-id={widget_id(@row.path)}
            phx-click="expand_widget"
            phx-value-id={widget_id(@row.path)}
          />
        </div>
      </div>
      <div class="job-overview-metrics">
        <div class="job-overview-activity">
          <.chart
            id={"job-activity-" <> Base.url_encode64(@row.path, padding: false)}
            class="job-overview-sparkline"
            payload={
              %{
                presentation: "sparkline",
                compact: true,
                axes: true,
                y_labels: false,
                chart_type: "bar",
                stacked: true,
                timezone: @timezone,
                series: Enum.map(@row.series, &Map.put(&1, :color, TraceStates.color(&1.state)))
              }
            }
            label={"Activity for " <> @row.path}
          />
        </div>
        <div class="job-overview-gauges">
          <.gauge
            id={"job-duration-" <> Base.url_encode64(@row.path, padding: false)}
            title="Duration"
            icon="hero-bolt"
            summary={@row.duration}
            unit="ms"
            timezone={@timezone}
          />
          <.gauge
            id={"job-lines-" <> Base.url_encode64(@row.path, padding: false)}
            title="Lines"
            icon="sidebar-traces"
            summary={@row.lines}
            unit=""
            timezone={@timezone}
            unavailable={if @state not in [nil, ""], do: "Available with Any state."}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :row, :map, required: true

  defp status_indicator(assigns) do
    tooltip =
      case assigns.row.state_distribution do
        [] ->
          "State slices: No traces in this timeframe"

        states ->
          "State slices · " <>
            Enum.map_join(states, " · ", fn item ->
              "#{String.capitalize(item.state)}: #{percentage(item.percentage)}%"
            end)
      end

    assigns =
      assigns
      |> assign(:pie_tooltip, tooltip)
      |> assign(
        :state_segments,
        Enum.map(assigns.row.state_distribution, fn item ->
          %{
            name: String.capitalize(item.state),
            value: item.count,
            color: TraceStates.color(item.state)
          }
        end)
      )

    ~H"""
    <div class="job-overview-status">
      <.chart
        id={"job-state-pie-" <> Base.url_encode64(@row.path, padding: false)}
        class="job-overview-status-circle"
        payload={
          %{
            presentation: "proportion",
            layout: "pie",
            outline_color: TraceStates.color("success"),
            segments: @state_segments
          }
        }
        label={@pie_tooltip}
        tooltip={@pie_tooltip}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :summary, :map, required: true
  attr :unit, :string, required: true
  attr :timezone, :string, required: true
  attr :unavailable, :any, default: nil
  attr :maximum, :any, default: nil
  attr :higher_is_better, :boolean, default: false
  attr :class, :string, default: ""

  defp gauge(assigns) do
    assigns =
      assigns
      |> assign(:latest_label, measurement(assigns.summary.latest, assigns.unit))
      |> assign(:average_label, measurement(assigns.summary.average, assigns.unit))

    ~H"""
    <div class={["job-overview-gauge", @class]}>
      <p :if={@unavailable} class="mt-2 text-center text-xs text-slate-500 dark:text-slate-400">
        {@unavailable}
      </p>
      <.chart
        :if={!@unavailable}
        id={@id}
        class="job-overview-gauge-chart"
        payload={
          %{
            presentation: "gauge",
            title: @title,
            comparison_colors: %{
              lower: ChartColors.color_at(if @higher_is_better, do: 2, else: 0),
              higher: ChartColors.color_at(if @higher_is_better, do: 0, else: 2),
              equal: ChartColors.color_at(8)
            },
            compact: true,
            show_value: false,
            timezone: @timezone,
            gauge: @summary |> Map.put(:unit, @unit) |> Map.put(:maximum, @maximum)
          }
        }
        label={"#{@title}: Average #{@average_label.value} #{@average_label.unit}; Latest #{@latest_label.value} #{@latest_label.unit}"}
      >
        <div class="job-overview-gauge-value" data-gauge-value aria-hidden="true">
          <TrifleApp.SidebarIcons.icon
            name={@icon}
            class="job-overview-gauge-icon text-slate-500 dark:text-slate-400"
          />
          <span class="job-overview-gauge-reading" data-gauge-reading>
            <span data-compact-value>{@latest_label.value}</span>
          </span>
          <span data-compact-unit class="job-overview-gauge-unit text-slate-500 dark:text-slate-400">
            {@latest_label.unit}
          </span>
        </div>
      </.chart>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :payload, :map, required: true
  attr :label, :string, required: true
  attr :class, :string, required: true
  attr :tooltip, :string, default: nil
  slot :inner_block

  defp chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="CompactChart"
      data-compact-chart
      data-chart={Jason.encode!(@payload)}
      role="img"
      aria-label={@label}
      data-tooltip={@tooltip}
      tabindex={if @tooltip, do: "0"}
      class={@class}
    >
      <div id={@id <> "-canvas"} phx-update="ignore" class="h-full w-full" data-compact-canvas></div>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp format(nil), do: "—"

  defp format(n) when is_number(n) and abs(n) >= 1_000,
    do: TrifleApp.ExploreCore.format_number(n)

  defp format(n) when is_integer(n), do: Integer.to_string(n)

  defp format(n) do
    n
    |> :erlang.float_to_binary(decimals: if(abs(n) < 10, do: 2, else: 1))
    |> String.replace(~r/(\.\d*?)0+$/, "\\1")
    |> String.trim_trailing(".")
  end

  defp measurement(value, "ms"), do: TrifleApp.Format.compact_duration_ms(value)

  defp measurement(value, "") do
    label = format(value)

    case Regex.run(~r/^(.+?)([kmbt])$/i, label) do
      [_, number, suffix] -> %{value: number, unit: suffix}
      _ -> %{value: label, unit: ""}
    end
  end

  defp measurement(value, unit), do: %{value: format(value), unit: unit}

  defp percentage(value) do
    rounded = Float.round(value * 1.0, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
