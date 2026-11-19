defmodule TrifleApp.Components.TraceOverviewTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TrifleApp.Components.TraceOverview

  @endpoint TrifleWeb.Endpoint

  test "HEEx owns the cards and only chart canvases ignore LiveView patches" do
    metrics = Map.new(1..6, &{"jobs/#{&1}", %{at: [1000], values: [%{"count" => 1}]}})

    overview =
      Trifle.Traces.Overview.build(
        %{catalog: %{at: [1000], values: [%{}]}, metrics: metrics},
        nil,
        nil,
        %{}
      )

    doc =
      render_component(&TraceOverview.content/1,
        overview: overview,
        params: %{},
        path_colors: %{},
        timezone: "UTC"
      )
      |> Floki.parse_document!()

    assert length(Floki.find(doc, "#traces-overview-grid > article")) == 6
    assert length(Floki.find(doc, "[phx-hook='CompactChart']")) == 24
    assert length(Floki.find(doc, "[data-compact-canvas][phx-update='ignore']")) == 24
    assert length(Floki.find(doc, ".job-overview-status-circle")) == 6
    assert Floki.find(doc, "#traces-overview-grid[phx-update='ignore']") == []
    assert Floki.find(doc, "[data-widget-payload], [phx-hook='DashboardGrid']") == []
    assert length(Floki.find(doc, ".grid-widget-expand[phx-click='expand_widget']")) == 6
  end

  test "expanded chart puts counts on the main axis and duration on the right, keeping lines in raw points" do
    overview =
      Trifle.Traces.Overview.build(
        %{
          catalog: %{at: [1000], values: [%{}]},
          metrics: %{
            "jobs/worker" => %{
              at: [1000],
              values: [
                %{
                  "count" => 1,
                  "states" => %{"success" => 1},
                  "duration" => %{"sum" => 12, "count" => 1},
                  "entries" => %{"count" => 9}
                }
              ]
            }
          }
        },
        nil,
        nil,
        %{}
      )

    doc =
      render_component(&TraceOverview.expanded/1,
        row: hd(overview.rows),
        path_colors: %{},
        timezone: "UTC"
      )
      |> Floki.parse_document!()

    [encoded] = Floki.attribute(doc, "[phx-hook='ExpandedWidgetView']", "data-chart")
    assert Floki.find(doc, "[data-role='table-root']") != []
    assert Floki.find(doc, "[data-role='timeline-controls'], [data-timeline-page]") == []
    chart = Jason.decode!(encoded)
    assert length(chart["series"]) == 2
    assert Enum.any?(chart["series"], &(&1["state"] == "success"))

    assert Enum.any?(
             chart["series"],
             &(&1["name"] == "Average duration" and &1["y_axis"] == "secondary")
           )

    refute Enum.any?(chart["series"], &(&1["name"] == "Average lines"))
    assert hd(chart["points"])["lines"] == 9
  end

  test "customer-controlled paths remain escaped in normal LiveView markup" do
    path = ~s|jobs/<img src=x onerror="alert(1)">|

    overview =
      Trifle.Traces.Overview.build(
        %{
          catalog: %{at: [1000], values: [%{}]},
          metrics: %{path => %{at: [1000], values: [%{"count" => 1}]}}
        },
        nil,
        nil,
        %{}
      )

    doc =
      render_component(&TraceOverview.content/1,
        overview: overview,
        params: %{},
        path_colors: %{},
        timezone: "UTC"
      )
      |> Floki.parse_document!()

    assert Floki.find(doc, "img, script") == []
    assert Floki.attribute(doc, "[data-trace-path]", "data-trace-path") == [path]
    assert Floki.find(doc, "[data-trace-path]") |> Floki.text() == path
  end

  test "trace and line counts use compact formatting and duration labels adapt units" do
    for {count, duration, duration_value, duration_unit, count_value, count_suffix} <- [
          {15_534, 4_125, "4.1", "s", "15.5", "k"},
          {22_512_623, 150_000, "2.5", "m", "22.5", "m"},
          {999, 0, "0", "ms", "999", ""},
          {0, 0, "0", "ms", "0", ""}
        ] do
      row = %{
        path: "jobs/worker",
        count: count,
        success: 100.0,
        state_distribution: [%{state: "success", count: count, percentage: 100.0}],
        duration: %{average: duration, latest: duration, latest_at: 1000},
        lines: %{average: count, latest: count, latest_at: 1000},
        series: []
      }

      overview = %{
        rows: [row],
        total: 1,
        pages: 1,
        page: 1,
        size: 9,
        row_count: 3,
        columns: 3,
        sort: "count",
        direction: "desc",
        collapsed: false
      }

      doc =
        render_component(&TraceOverview.content/1,
          overview: overview,
          params: %{},
          path_colors: %{},
          timezone: "UTC"
        )
        |> Floki.parse_document!()

      label = count_value <> count_suffix

      assert Floki.find(doc, ".job-overview-gauge[title]") == []

      assert Floki.find(doc, ".job-overview-counter strong") |> Floki.text() |> String.trim() ==
               label

      assert Floki.find(doc, "[id^='job-lines-'] [data-compact-value]") |> Floki.text() ==
               count_value

      assert Floki.find(doc, "[id^='job-lines-'] [data-compact-unit]")
             |> Floki.text()
             |> String.trim() == count_suffix

      assert Floki.find(doc, "[id^='job-duration-'] [data-compact-value]") |> Floki.text() ==
               duration_value

      assert Floki.find(doc, "[id^='job-duration-'] [data-compact-unit]")
             |> Floki.text()
             |> String.trim() == duration_unit

      [payload] = Floki.attribute(doc, "[id^='job-duration-'][data-chart]", "data-chart")
      assert Jason.decode!(payload)["gauge"]["latest"] == duration
    end
  end
end
