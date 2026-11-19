defmodule TrifleApp.Components.TraceOverviewTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias TrifleApp.Components.TraceOverview
  alias TrifleApp.Components.DashboardWidgets.{Registry, Types}

  @endpoint TrifleWeb.Endpoint

  test "read-only dashboard widgets occupy three columns per row and remain internal" do
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

    [grid] = Floki.attribute(doc, "#traces-overview-grid", "data-initial-grid")
    widgets = Jason.decode!(grid)

    assert Enum.map(widgets, &{&1["x"], &1["y"], &1["w"]}) == [
             {0, 0, 4},
             {4, 0, 4},
             {8, 0, 4},
             {0, 10, 4},
             {4, 10, 4},
             {8, 10, 4}
           ]

    assert Floki.attribute(doc, "#traces-overview-grid", "data-editable") == ["false"]
    assert length(Floki.find(doc, ".grid-widget-expand")) == 6
    assert Floki.find(doc, ".grid-widget-edit") == []
    assert Registry.type_module("trace_overview") == Types.TraceOverview
    refute Types.TraceOverview in Registry.modules()
    assert Registry.editor_module("trace_overview") == nil
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

  test "trace and line counts use compact formatting and duration labels adapt units" do
    for {count, duration, duration_value, duration_unit} <- [
          {15_213, 4_125, "4.1", "s"},
          {22_512_623, 150_000, "2.5", "m"}
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

      label = if count == 15_213, do: "15.2k", else: "22.5m"

      assert Floki.find(doc, ".job-overview-gauge[title]") == []

      assert Floki.find(doc, ".job-overview-counter strong") |> Floki.text() |> String.trim() ==
               label

      assert Floki.find(doc, "[id^='job-lines-'] [data-compact-value]") |> Floki.text() == label

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
