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
    widgets =
      assigns.overview.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, index} ->
        %{
          "id" => widget_id(row.path),
          "type" => "trace_overview",
          "title" => row.path,
          "x" => rem(index, 3) * 4,
          "y" => div(index, 3) * 10,
          "w" => 4,
          "h" => 10
        }
      end)

    datasets =
      Map.new(assigns.overview.rows, fn row ->
        widget_assigns =
          assigns
          |> Map.take([:params, :path_colors, :timezone, :state])
          |> Map.merge(%{row: row, __changed__: nil})

        html = widget(widget_assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
        id = widget_id(row.path)
        {id, %{id: id, presentation: "trace_overview", html: html}}
      end)

    assigns =
      assigns
      |> assign(:dashboard, %{id: "traces-overview", payload: %{"grid" => widgets}})
      |> assign(:datasets, datasets)

    ~H"""
    <section
      id="trace-overview"
      aria-label="Overview"
      class="shrink-0 rounded-lg border border-slate-200 bg-white dark:border-slate-700 dark:bg-slate-900"
    >
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
            <select name="jobs_sort" class="job-overview-select">
              <option
                :for={
                  {label, value} <- [
                    {"Traces", "count"},
                    {"Name", "name"},
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
          <label>
            <span class="sr-only">Sort direction</span><select
              name="jobs_direction"
              class="job-overview-select"
            >
            <option value="desc" selected={@overview.direction == "desc"}>Descending</option><option
              value="asc"
              selected={@overview.direction == "asc"}
            >Ascending</option>
          </select>
          </label>
          <label>
            Traces
            <select name="jobs_size" class="job-overview-select">
              <option :for={size <- [3, 9, 15, 30]} value={size} selected={@overview.size == size}>
                {size}
              </option>
            </select>
          </label>
          <nav
            :if={!@loading && !@error && @overview.total > 0}
            aria-label="Overview pagination"
            class="ml-2 flex items-center gap-3 border-l border-slate-200 pl-4 dark:border-slate-700"
          >
            <span class="whitespace-nowrap tabular-nums text-slate-500 dark:text-slate-400">
              Page {@overview.page} of {@overview.pages}
            </span>
            <button
              type="button"
              phx-click="overview_page"
              phx-value-page={@overview.page - 1}
              disabled={@overview.page <= 1}
              class="disabled:opacity-40"
            >
              Previous
            </button>
            <button
              type="button"
              phx-click="overview_page"
              phx-value-page={@overview.page + 1}
              disabled={@overview.page >= @overview.pages}
              class="disabled:opacity-40"
            >
              Next
            </button>
          </nav>
        </form>
      </div>
      <div :if={!@overview.collapsed} id="job-overview-body" aria-busy={to_string(@loading)}>
        <p :if={@loading} class="p-6 text-sm text-slate-500">Loading job activity…</p>
        <p :if={@error} role="alert" class="p-6 text-sm text-red-600">{@error}</p>
        <p :if={!@loading && !@error && @overview.rows == []} class="p-6 text-sm text-slate-500">
          No recorded jobs match this path, state and timeframe.
        </p>
        <div :if={!@loading && !@error} class="job-overview-grid">
          <TrifleApp.Components.DashboardWidgets.WidgetView.grid
            grid_dom_id="traces-overview-grid"
            dashboard={@dashboard}
            min_rows={1}
            compact={true}
            timeseries={@datasets}
            hide_on_patch={false}
            widget_export={%{type: :disabled}}
          />
        </div>
      </div>
    </section>
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
          <.status_indicators row={@row} />
          <.link
            patch={Query.path_url(@params, @row.path)}
            class="job-overview-title text-base font-semibold hover:underline underline-offset-2"
            data-trace-path={@row.path}
          >
            {PathColors.html(@row.path, @path_colors, "/")}
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

  defp status_indicators(assigns) do
    success = assigns.row.success

    success_tooltip =
      if is_number(success),
        do: "Success rate: #{percentage(success)}%",
        else: "Success rate: No traces in this timeframe"

    state_tooltip =
      case assigns.row.state_distribution do
        [] ->
          "State mix: No traces in this timeframe"

        states ->
          "State mix · " <>
            Enum.map_join(states, " · ", fn item ->
              "#{String.capitalize(item.state)}: #{percentage(item.percentage)}%"
            end)
      end

    assigns =
      assigns
      |> assign(:success_tooltip, success_tooltip)
      |> assign(:state_tooltip, state_tooltip)
      |> assign(:pie_tooltip, String.replace_prefix(state_tooltip, "State mix", "State slices"))
      |> assign(
        :success_segments,
        if(is_number(success),
          do: [
            %{name: "Success", value: success, color: TraceStates.color("success")},
            %{name: "Other states", value: 100 - success}
          ],
          else: []
        )
      )
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
        id={"job-success-rate-" <> Base.url_encode64(@row.path, padding: false)}
        class="job-overview-status-circle"
        payload={
          %{
            presentation: "proportion",
            outline_color: TraceStates.color("success"),
            segments: @success_segments
          }
        }
        label={@success_tooltip}
        tooltip={@success_tooltip}
      />
      <.chart
        id={"job-state-mix-" <> Base.url_encode64(@row.path, padding: false)}
        class="job-overview-status-circle"
        payload={
          %{
            presentation: "proportion",
            outline_color: TraceStates.color("success"),
            segments: @state_segments
          }
        }
        label={@state_tooltip}
        tooltip={@state_tooltip}
      />
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
          <span class="job-overview-gauge-reading" data-gauge-reading>
            <TrifleApp.SidebarIcons.icon
              name={@icon}
              class="h-5 w-5 shrink-0 text-slate-500 dark:text-slate-400"
            />
            <span data-compact-value>{@latest_label.value}</span>
          </span>
          <span
            :if={@unit != ""}
            data-compact-unit
            class="job-overview-gauge-unit text-slate-500 dark:text-slate-400"
          >
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
  defp measurement(value, unit), do: %{value: format(value), unit: unit}

  defp percentage(value) do
    rounded = Float.round(value * 1.0, 1)

    if rounded == trunc(rounded),
      do: Integer.to_string(trunc(rounded)),
      else: Float.to_string(rounded)
  end
end
