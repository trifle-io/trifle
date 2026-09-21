defmodule TrifleApp.TracesLiveTest do
  use TrifleApp.ConnCase
  import Phoenix.LiveViewTest
  import Trifle.OrganizationsFixtures
  import Trifle.BillingFixtures
  alias Trifle.Organizations
  alias Trifle.Traces.TraceRecord

  defmodule FakeReader do
    def search(_, _, filters) do
      send(Application.fetch_env!(:trifle, :trace_test_pid), {:trace_search, filters})

      if filters[:state] == "error" do
        {:ok, %{traces: [], cursor: nil}}
      else
        reference = if filters[:cursor], do: "second", else: "first"

        {:ok,
         %{traces: [record(reference)], cursor: if(reference == "first", do: "cursor", else: nil)}}
      end
    end

    def detail(_, _, "slow") do
      send(Application.fetch_env!(:trifle, :trace_test_pid), {:slow_detail, self()})

      receive do
        :finish -> {:ok, record("slow")}
      end
    end

    def detail(_, _, "missing"), do: {:error, :not_found}
    def detail(_, _, reference), do: {:ok, record(reference)}

    def part(_, _, reference, n) do
      pid = Application.fetch_env!(:trifle, :trace_test_pid)
      send(pid, {:trace_part, reference, n})

      if reference == "controlled" do
        send(pid, {:waiting_part, n, self()})
        receive do: (:finish -> :ok)
      end

      if reference == "part-error" && n == 3 do
        {:error, :storage_unavailable}
      else
        {:ok,
         [
           %{
             part: n,
             row: 0,
             entry: %{
               at: 1_700_000_000,
               state: :success,
               type: :text,
               message: "<script>part #{n}</script>"
             }
           }
         ]}
      end
    end

    def artifact(_, _, _, _, _), do: {:ok, %{name: "report.txt", body: "safe text"}}

    def attachments(_, _, reference, after_part) do
      send(
        Application.fetch_env!(:trifle, :trace_test_pid),
        {:trace_attachments, reference, after_part}
      )

      if reference == "slow-attachments" do
        send(Application.fetch_env!(:trifle, :trace_test_pid), {:slow_attachments, self()})
        receive do: (:finish -> :ok)
      end

      if reference == "attachments-error" do
        {:error, :storage_unavailable}
      else
        {:ok,
         %{
           attachments: [
             %{
               name: "#{reference}-#{after_part}.txt",
               part: after_part + 1,
               row: 0,
               size: 102_400
             }
           ],
           next_part: if(after_part == 0, do: 1)
         }}
      end
    end

    defp record(reference),
      do: %TraceRecord{
        reference: reference,
        key: "jobs/App.Worker",
        meta: %{"monitor_id" => reference},
        first_at: ~U[2026-09-12 12:00:00Z],
        state: :success,
        tags: ["queue:default", "scheduled"],
        duration: 125,
        counters: %{types: %{media: 1}},
        parts:
          case reference do
            "empty" -> 0
            "single" -> 1
            "ten" -> 10
            "hundred" -> 100
            ref when ref in ["many", "controlled"] -> 102
            "part-error" -> 12
            _ -> 2
          end,
        length: 2
      }
  end

  defmodule FakeDurationActivity do
    def fetch(a, b, c, d, e) do
      {:ok, activity} = TrifleApp.TracesLiveTest.FakeActivity.fetch(a, b, c, d, e)

      metrics =
        Map.new(activity.metrics, fn {key, metric} ->
          values =
            Enum.map(metric.values, fn value ->
              states =
                Map.new(value["states"], fn {state, count} ->
                  duration =
                    %{"success" => 100, "warning" => 900, "error" => 500, "running" => 400}[state]

                  {state, %{"count" => count, "sum" => count * duration}}
                end)

              sum = states |> Map.values() |> Enum.map(& &1["sum"]) |> Enum.sum()

              Map.put(value, "duration", %{
                "count" => value["count"],
                "sum" => sum,
                "states" => states
              })
            end)

          {key, %{metric | values: values}}
        end)

      {:ok, %{activity | metrics: metrics}}
    end
  end

  defmodule FakeActivity do
    def fetch(_, _, _, _, granularity) do
      send(Application.fetch_env!(:trifle, :trace_test_pid), {:trace_activity, granularity})
      at = [~U[2026-09-12 12:00:00Z], ~U[2026-09-12 13:00:00Z]]

      {:ok,
       %{
         catalog: %{
           at: at,
           values: [
             %{"keys" => %{"jobs/A.Worker" => 0, "jobs/App.Worker" => 2, "requests/get" => 3}},
             %{"keys" => %{"jobs/App.Worker" => 1}}
           ]
         },
         metrics: %{
           "jobs/App.Worker" => %{
             at: at,
             values: [
               %{"count" => 2, "states" => %{"success" => 1, "warning" => 1}},
               %{"count" => 1, "states" => %{"error" => 1}}
             ]
           },
           "requests/get" => %{at: at, values: [%{"count" => 3, "states" => %{"running" => 3}}]}
         }
       }}
    end
  end

  setup %{conn: conn} do
    previous =
      for key <- [:trace_reader, :trace_activity, :trace_test_pid],
          into: %{},
          do: {key, Application.fetch_env(:trifle, key)}

    on_exit(fn ->
      Enum.each(previous, fn
        {key, {:ok, value}} -> Application.put_env(:trifle, key, value)
        {key, :error} -> Application.delete_env(:trifle, key)
      end)
    end)

    Application.put_env(:trifle, :trace_reader, FakeReader)
    Application.put_env(:trifle, :trace_activity, FakeActivity)
    Application.put_env(:trifle, :trace_test_pid, self())
    user = Trifle.AccountsFixtures.user_fixture()
    org = organization_fixture(%{user: user})
    app_entitlement_fixture(org)

    {:ok, database} =
      Organizations.create_database_for_org(org, %{
        display_name: "Trace source",
        driver: "postgres",
        host: "postgres",
        port: 5432,
        database_name: "test",
        username: "test",
        password: "test",
        granularities: ["1h", "1d"],
        trace_config: %{
          "index_name" => "trace_ui_test",
          "data_driver" => "file",
          "data_path" => "/tmp/trace-ui-test",
          "retention_days" => 7,
          "gzip" => false
        }
      })

    %{conn: log_in_user(conn, user), database: database, organization: org}
  end

  test "list and detail share sibling colors from all known paths, not just visible traces", %{
    conn: conn,
    database: database
  } do
    alias TrifleApp.DesignSystem.ChartColors
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=first")
    html = render_async(view)
    {:ok, doc} = Floki.parse_document(html)
    list_styles = Floki.attribute(doc, "#trace-list [data-trace-path] span", "style")
    detail_styles = Floki.attribute(doc, "#trace-detail [data-trace-path] a", "style")

    assert list_styles == [
             "color: #{ChartColors.color_for(0)} !important",
             "color: #{ChartColors.color_for(1)} !important"
           ]

    assert detail_styles == list_styles

    assert Enum.map(Floki.find(doc, "#trace-list [data-trace-path] span"), &Floki.text/1) == [
             "jobs/",
             "App.Worker"
           ]

    view |> form("#trace-filters", %{path: "jobs", state: "error"}) |> render_submit()
    {:ok, filtered} = view |> render_async() |> Floki.parse_document()
    assert Floki.find(filtered, "#trace-list [data-trace-path]") == []

    assert Floki.attribute(filtered, "#trace-detail [data-trace-path] a", "style") ==
             list_styles
  end

  test "activity and detail share one scrollport below FilterBar with native sticky header", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=first")
    html = render_async(view)
    doc = Floki.parse_document!(html)

    assert Floki.find(
             doc,
             "#traces-root.traces-workspace > .traces-scrollport > .traces-content > #trace-panels.trace-panels"
           ) != []

    assert Floki.find(doc, "#trace-panels > #trace-list.trace-list-split.overflow-auto") != []
    assert Floki.find(doc, "#trace-panels > #trace-detail.overflow-auto") == []
    assert Floki.find(doc, "#trace-detail > #trace-detail-header.sticky") != []
    assert Floki.find(doc, ".traces-scrollport [data-filter-bar-shortcuts]") == []

    assert Floki.find(doc, ".trace-list-rows.overflow-y-auto, .trace-entry-body.overflow-auto") ==
             []

    refute html =~ "max-h-[65vh]"
    refute Floki.attribute(doc, "#traces-root", "class") |> hd() =~ "min-h-screen"

    view |> element("button[phx-click='close_trace']") |> render_click()
    assert has_element?(view, "#trace-panels > #trace-list.overflow-auto")
    refute has_element?(view, "#trace-list.trace-list-split")
    refute has_element?(view, "#trace-detail")
  end

  test "list metadata comes from the trace index before any detail is selected", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}")
    render_async(view)

    assert has_element?(view, "#trace-list [data-trace-metadata='entries'] dd", "2")
    assert has_element?(view, "#trace-list [data-trace-metadata='tags'] dd", "2")
    assert has_element?(view, "#trace-list [data-trace-metadata='attachments'] dd", "1")
    assert has_element?(view, "#trace-list [data-trace-metadata='duration'] dd", "125 ms")
    assert has_element?(view, "#trace-list .trace-row-timing", "2026-09-12 12:00:00 UTC")
    refute has_element?(view, "#trace-list .trace-row-timing", "125 ms")
    refute has_element?(view, "#trace-detail")
  end

  test "argument header follows the selected trace without querying activity again", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=first")
    render_async(view)
    assert_receive {:trace_activity, _}

    assert has_element?(
             view,
             "#trace-arguments-#{database.id}-first [data-arguments-preview]",
             ~s({"monitor_id":"first"})
           )

    view |> form("#trace-reference", %{reference: "second"}) |> render_submit()
    render_async(view)
    refute has_element?(view, "#trace-arguments-#{database.id}-first")

    assert has_element?(
             view,
             "#trace-arguments-#{database.id}-second [data-arguments-preview]",
             ~s({"monitor_id":"second"})
           )

    refute_receive {:trace_activity, _}
  end

  test "trace filters attach below FilterBar and retain LiveView updates and submit handling", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}")
    render_async(view)

    attachment = "#traces-filter-bar-shortcuts.sticky > #traces-filter-bar-attachment"
    assert has_element?(view, "#{attachment} #trace-filters")
    assert has_element?(view, "#{attachment} #trace-paths option[value='jobs/App.Worker']")
    refute has_element?(view, "#{attachment} #smart_timeframe")
    refute has_element?(view, "#{attachment} #traces-dashboard-grid")

    view
    |> form("#{attachment} #trace-filters", %{path: "jobs", state: "warning"})
    |> render_submit()

    render_async(view)
    assert has_element?(view, "#{attachment} #trace-filter-path[value='jobs']")

    assert has_element?(
             view,
             "#{attachment} #trace-filter-state option[value='warning'][selected]"
           )

    assert [%{"path" => "jobs/App.Worker", "state" => "warning"}] =
             activity_payload(view)["series"]

    assert activity_total(view) == 1
  end

  test "path segments and tags navigate to the filtered list, clearing detail expansion", %{
    conn: conn,
    database: database
  } do
    for {selector, filter, value} <- [
          {"#trace-detail [data-trace-path] a:first-child", :segment, "jobs"},
          {"#trace-detail [data-trace-tag='queue:default']", :tags, %{any: ["queue:default"]}}
        ] do
      {:ok, view, _} =
        live(
          conn,
          ~p"/traces?source_id=#{database.id}&reference=first&detail=expanded&timeframe=2d"
        )

      render_async(view)
      assert_receive {:trace_search, _}
      view |> element(selector) |> render_click()
      render_async(view)
      params = URI.decode_query(URI.parse(assert_patch(view)).query)
      assert params["source_id"] == database.id
      assert params["timeframe"] == "2d"
      refute Map.has_key?(params, "reference")
      refute Map.has_key?(params, "detail")
      refute has_element?(view, "#trace-detail")
      assert has_element?(view, "#trace-list:not(.hidden)")
      assert_receive {:trace_search, filters}
      assert filters[filter] == value
    end
  end

  test "footer buttons switch panels, collapse on repeat clicks and reset for a new trace", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=first")
    render_async(view)

    assert has_element?(view, "#trace-detail-footer")
    refute has_element?(view, "#trace-detail-footer .trace-footer-panel:not([hidden])")

    for section <- ~w(tags metadata attachments tags) do
      view |> element("button[phx-value-section='#{section}']") |> render_click()
      render_async(view)

      assert has_element?(view, "button[phx-value-section='#{section}'][aria-expanded='true']")
      doc = view |> render() |> Floki.parse_document!()
      [panel_id] = Floki.attribute(doc, "button[phx-value-section='#{section}']", "aria-controls")

      assert length(Floki.find(doc, "#trace-detail-footer .trace-footer-panel:not([hidden])")) ==
               1

      assert has_element?(view, "##{panel_id}:not([hidden])")
    end

    view |> element("button[phx-value-section='tags']") |> render_click()
    refute has_element?(view, "#trace-detail-footer .trace-footer-panel:not([hidden])")
    refute has_element?(view, "#trace-detail-footer button[aria-expanded='true']")

    view |> element("button[phx-value-section='metadata']") |> render_click()
    view |> form("#trace-reference", %{reference: "second"}) |> render_submit()
    render_async(view)

    refute has_element?(view, "#trace-detail-footer .trace-footer-panel:not([hidden])")
    refute has_element?(view, "#trace-detail-footer button[aria-expanded='true']")
  end

  test "attachments are fetched lazily, paginated independently and reset for a new trace", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=many")
    render_async(view)
    refute_receive {:trace_attachments, _, _}
    refute has_element?(view, "[data-trace-attachments]:not([hidden])")

    view |> element("button[phx-value-section='attachments']") |> render_click()
    render_async(view)
    assert_receive {:trace_attachments, "many", 0}
    assert has_element?(view, "[data-trace-attachments]:not([hidden])")
    assert has_element?(view, "[data-trace-attachments] a[href*='part=1']", "many-0.txt")

    assert has_element?(
             view,
             "[data-trace-attachments] [data-attachment-size][data-size-bytes='102400']",
             "100 KiB"
           )

    refute has_element?(view, "#trace-entry-101-0")

    view |> element("button[phx-value-section='attachments']") |> render_click()
    refute has_element?(view, "[data-trace-attachments]:not([hidden])")
    view |> element("button[phx-value-section='attachments']") |> render_click()
    assert has_element?(view, "[data-trace-attachments]:not([hidden])")
    refute_receive {:trace_attachments, _, _}
    view |> element("button[phx-click='more_attachments']") |> render_click()
    render_async(view)
    assert_receive {:trace_attachments, "many", 1}
    assert has_element?(view, "[data-trace-attachments] a", "many-0.txt")
    assert has_element?(view, "[data-trace-attachments] a[href*='part=2']", "many-1.txt")
    refute has_element?(view, "#trace-entry-101-0")
    refute has_element?(view, "button[phx-click='more_attachments']")

    view |> form("#trace-reference", %{reference: "second"}) |> render_submit()
    render_async(view)
    assert has_element?(view, "#trace-attachments-second")
    refute has_element?(view, "[data-trace-attachments]:not([hidden])")
    refute has_element?(view, "[data-trace-attachments] a")
    refute_receive {:trace_attachments, _, _}
  end

  test "collapsing attachments while they load keeps the finished list collapsed", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=slow-attachments")
    render_async(view)
    view |> element("button[phx-value-section='attachments']") |> render_click()
    assert_receive {:slow_attachments, pid}, 1000
    assert has_element?(view, "[data-trace-attachments]:not([hidden])")
    view |> element("button[phx-value-section='attachments']") |> render_click()
    send(pid, :finish)
    render_async(view)
    assert has_element?(view, "[data-trace-attachments] a", "slow-attachments-0.txt")
    refute has_element?(view, "[data-trace-attachments]:not([hidden])")
    view |> element("button[phx-value-section='attachments']") |> render_click()
    assert has_element?(view, "[data-trace-attachments]:not([hidden])")
    refute_receive {:slow_attachments, _}
  end

  test "attachment errors can be retried and late results cannot cross trace selections", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=attachments-error")
    render_async(view)
    view |> element("button[phx-value-section='attachments']") |> render_click()
    render_async(view)
    assert_receive {:trace_attachments, "attachments-error", 0}

    assert has_element?(
             view,
             "[data-trace-attachments] [role='status']",
             "Attachments could not be loaded"
           )

    view |> element("button[phx-click='retry_attachments']") |> render_click()
    render_async(view)
    assert_receive {:trace_attachments, "attachments-error", 0}

    view |> form("#trace-reference", %{reference: "slow-attachments"}) |> render_submit()
    render_async(view)
    view |> element("button[phx-value-section='attachments']") |> render_click()
    assert_receive {:slow_attachments, pid}, 1000
    view |> form("#trace-reference", %{reference: "first"}) |> render_submit()
    send(pid, :finish)
    render_async(view)
    assert has_element?(view, "#trace-attachments-first")
    refute has_element?(view, "[data-trace-attachments] a")
    refute has_element?(view, "[data-trace-attachments] [role='status']")
  end

  test "mailbox, pagination, deep links and multipart detail", %{conn: conn, database: database} do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&timeframe=1d&granularity=1h")
    html = render_async(view)
    assert html =~ "Activity · All traces"
    assert activity_total(view) == 6
    refute html =~ "recorded events"
    assert has_element?(view, "#traces-root > h1.sr-only", "Traces")
    refute has_element?(view, "#traces-root > header")
    refute has_element?(view, "button[phx-click='toggle_source_dropdown']")
    assert has_element?(view, "#traces-dashboard-grid[data-editable='false'][data-min-rows='3']")
    assert has_element?(view, ".grid-widget-expand[data-widget-id='trace-activity']")
    refute has_element?(view, "#trace-activity-chart[phx-hook='DatabaseExploreChart']")
    refute has_element?(view, "#traces-dashboard-grid [data-export-link]")
    assert has_element?(view, "#trace-list a", "jobs/App.Worker")
    refute has_element?(view, "#trace-detail")
    view |> element("button", "Load more") |> render_click()
    render_async(view)
    assert has_element?(view, "#trace-list a[href*='second']")
    view |> element("#trace-list a[href*='first']") |> render_click()
    html = render_async(view)
    assert html =~ "&lt;script&gt;part 1&lt;/script&gt;"
    assert has_element?(view, "#trace-entry-1-0", "2023-11-14 22:13:20 UTC")
    assert has_element?(view, "#trace-entry-1-0 .trace-entry-number", "1")
    assert html =~ "&lt;script&gt;part 2&lt;/script&gt;"
    refute has_element?(view, "button[phx-click='load_part']")
    assert has_element?(view, "#trace-entry-1-0 .trace-entry-number", "1")
    assert has_element?(view, "#trace-entry-2-0 .trace-entry-number", "2")
    assert has_element?(view, "[data-copy-text]", "Loaded parts: 2/2")
    assert has_element?(view, "[data-copy-text]", "<script>part 2</script>")
    view |> element("#trace-detail button[aria-label='Expand detail']") |> render_click()
    assert has_element?(view, "#trace-list.hidden")
    refute has_element?(view, "#trace-list[class~='md:block']")

    assert has_element?(
             view,
             "#trace-detail button[aria-label='Restore split view'][aria-pressed='true']"
           )

    view |> element("#trace-detail button[aria-label='Restore split view']") |> render_click()
    assert has_element?(view, "#trace-list[class~='md:block']")

    assert has_element?(
             view,
             "#trace-detail button[aria-label='Expand detail'][aria-pressed='false']"
           )

    view |> element("#trace-detail button[aria-label='Expand detail']") |> render_click()
    view |> element("#trace-detail button[aria-label='Close detail']") |> render_click()
    assert has_element?(view, "#trace-list:not(.hidden)")
    refute has_element?(view, "#trace-detail")
    refute render(view) =~ "Select a trace"
  end

  test "autoload stops at 100 parts and remaining parts load individually", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=many")
    render_async(view)

    for part <- 1..100 do
      assert_receive {:trace_part, "many", ^part}
      assert has_element?(view, "#trace-entry-#{part}-0 .trace-entry-number", to_string(part))
    end

    refute_receive {:trace_part, "many", 101}
    assert has_element?(view, "button[phx-click='load_part']", "100/102 loaded")
    assert has_element?(view, "[data-copy-text]", "Loaded parts: 100/102")
    refute has_element?(view, "[data-copy-text]", "part 101")
    refute has_element?(view, "#trace-detail-loading")

    view |> element("button[phx-click='load_part']") |> render_click()
    render_async(view)
    assert_receive {:trace_part, "many", 101}
    refute_receive {:trace_part, "many", 102}
    assert has_element?(view, "button[phx-click='load_part']", "101/102 loaded")

    view |> element("button[phx-click='load_part']") |> render_click()
    render_async(view)
    assert_receive {:trace_part, "many", 102}
    refute_receive {:trace_part, "many", _}
    assert has_element?(view, "#trace-entry-102-0 .trace-entry-number", "102")
    assert has_element?(view, "[data-copy-text]", "Loaded parts: 102/102")
    refute has_element?(view, "button[phx-click='load_part']")
  end

  test "parts load sequentially with progressive entries and an uninterrupted loading bar", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=controlled")

    for part <- 1..100 do
      assert_receive {:waiting_part, ^part, pid}, 1000
      assert_receive {:trace_part, "controlled", ^part}
      refute_receive {:trace_part, "controlled", _}, 10

      assert has_element?(
               view,
               "#trace-detail[aria-busy='true'] > #trace-detail-header > #trace-detail-loading"
             )

      refute has_element?(view, "button[phx-click='load_part']")
      assert has_element?(view, "[data-copy-text]", "Loaded parts: #{part - 1}/102")

      if part > 1 do
        assert has_element?(view, "#trace-entry-#{part - 1}-0")
      end

      # Duplicate user events cannot start an overlapping request.
      render_click(view, "load_part")
      refute_receive {:trace_part, "controlled", _}, 10
      send(pid, :finish)
    end

    render_async(view)
    assert has_element?(view, "#trace-entry-100-0")
    assert has_element?(view, "#trace-detail[aria-busy='false']")
    refute has_element?(view, "#trace-detail-loading")
    refute_receive {:trace_part, "controlled", 101}

    view |> element("button[phx-click='load_part']") |> render_click()
    assert_receive {:waiting_part, 101, pid}, 1000
    assert has_element?(view, "#trace-detail-loading")
    send(pid, :finish)
    render_async(view)
    refute has_element?(view, "#trace-detail-loading")
    refute_receive {:waiting_part, 102, _}
  end

  test "empty, short and exactly 100-part traces stop without a next-part button", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=empty")
    render_async(view)
    assert has_element?(view, "#trace-detail", "No stored entries yet.")
    refute_receive {:trace_part, "empty", _}

    for {reference, count} <- [{"single", 1}, {"ten", 10}, {"hundred", 100}] do
      view |> form("#trace-reference", %{reference: reference}) |> render_submit()
      render_async(view)

      for part <- 1..count, do: assert_receive({:trace_part, ^reference, ^part})

      refute_receive {:trace_part, ^reference, _}
      assert has_element?(view, "[data-copy-text]", "Loaded parts: #{count}/#{count}")
      refute has_element?(view, "button[phx-click='load_part']")
      refute has_element?(view, "#trace-detail-loading")
    end
  end

  test "part failures stop autoload, retain loaded content and allow retry", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=part-error")
    render_async(view)

    for part <- 1..3, do: assert_receive({:trace_part, "part-error", ^part})
    refute_receive {:trace_part, "part-error", _}
    assert has_element?(view, "#trace-entry-2-0")
    assert has_element?(view, "[data-copy-text]", "Loaded parts: 2/12")

    assert has_element?(
             view,
             "#trace-detail",
             "Stored content is missing, expired, or unavailable."
           )

    refute has_element?(view, "#trace-detail-loading")
    refute has_element?(view, "button[phx-click='load_part']")

    view |> element("button[phx-click='retry_detail']") |> render_click()
    render_async(view)
    for part <- 1..3, do: assert_receive({:trace_part, "part-error", ^part})
    assert has_element?(view, "#trace-entry-2-0 .trace-entry-number", "2")
  end

  test "switching or closing traces ignores in-flight parts and stops their autoload chain", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}")
    render_async(view)

    for action <- [:switch, :close] do
      view |> form("#trace-reference", %{reference: "controlled"}) |> render_submit()
      assert_receive {:waiting_part, 1, first_pid}, 1000
      send(first_pid, :finish)
      assert_receive {:waiting_part, 2, second_pid}, 1000
      assert has_element?(view, "#trace-entry-1-0")

      case action do
        :switch -> view |> form("#trace-reference", %{reference: "single"}) |> render_submit()
        :close -> view |> element("button[phx-click='close_trace']") |> render_click()
      end

      send(second_pid, :finish)
      render_async(view)
      refute_receive {:waiting_part, 3, _}
      refute has_element?(view, "#trace-entry-2-0")
      refute has_element?(view, "#trace-detail-loading")

      if action == :switch do
        assert has_element?(view, "[data-copy-text]", "Loaded parts: 1/1")
        refute has_element?(view, "#trace-detail", "controlled")
      else
        refute has_element?(view, "#trace-detail")
      end
    end
  end

  test "returning to the full-width list preserves filters and loaded rows", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} =
      live(
        conn,
        ~p"/traces?source_id=#{database.id}&path=jobs&state=success&timeframe=1d&granularity=1h"
      )

    render_async(view)
    assert_receive {:trace_activity, "1h"}
    assert_receive {:trace_search, _}

    view |> element("button", "Load more") |> render_click()
    render_async(view)
    assert_receive {:trace_search, _}

    view |> element("#trace-list a[href*='first']") |> render_click()
    render_async(view)
    assert has_element?(view, "#trace-detail")
    refute has_element?(view, "#trace-list button", "Expand list")
    assert URI.decode_query(URI.parse(assert_patch(view)).query)["reference"] == "first"

    view |> element("#trace-detail button[aria-label='Expand detail']") |> render_click()
    assert URI.decode_query(URI.parse(assert_patch(view)).query)["detail"] == "expanded"

    view |> element("#trace-detail button[aria-label='Close detail']") |> render_click()
    render_async(view)
    params = URI.decode_query(URI.parse(assert_patch(view)).query)
    refute Map.has_key?(params, "reference")
    refute Map.has_key?(params, "detail")

    assert Map.take(params, ~w(path state timeframe granularity)) == %{
             "path" => "jobs",
             "state" => "success",
             "timeframe" => "1d",
             "granularity" => "1h"
           }

    refute has_element?(view, "#trace-detail")
    assert has_element?(view, "#trace-list:not(.hidden) a[href*='first']")
    assert has_element?(view, "#trace-list:not(.hidden) a[href*='second']")

    # Reopening even the same trace returns to the split view.
    view |> element("#trace-list a[href*='first']") |> render_click()
    render_async(view)
    assert has_element?(view, "#trace-detail", "first")
    refute has_element?(view, "#trace-list button", "Expand list")
    refute_receive {:trace_search, _}
    refute_receive {:trace_activity, _}
  end

  test "detail layout URL patches preserve loaded rows, entries and activity", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} =
      live(
        conn,
        ~p"/traces?source_id=#{database.id}&reference=first&path=jobs&timeframe=1d&granularity=1h"
      )

    render_async(view)
    assert_receive {:trace_activity, _}
    assert_receive {:trace_search, _}
    original_activity = activity_payload(view)

    view |> element("button", "Load more") |> render_click()
    render_async(view)
    assert_receive {:trace_search, _}
    assert has_element?(view, "#trace-entry-2-0")

    view |> element("#trace-detail button[aria-label='Expand detail']") |> render_click()
    expanded_url = assert_patch(view)
    expanded_params = URI.decode_query(URI.parse(expanded_url).query)
    assert expanded_params["detail"] == "expanded"
    assert expanded_params["reference"] == "first"
    assert expanded_params["path"] == "jobs"
    assert has_element?(view, "#trace-detail button[aria-label='Restore split view']")
    refute has_element?(view, "#trace-list[class~='md:block']")

    view |> element("#trace-detail button[aria-label='Restore split view']") |> render_click()
    split_url = assert_patch(view)
    refute Map.has_key?(URI.decode_query(URI.parse(split_url).query), "detail")
    assert has_element?(view, "#trace-list[class~='md:block']")

    # Browser history sends these URLs through the same handle_params callback.
    render_patch(view, expanded_url)
    assert has_element?(view, "#trace-detail button[aria-label='Restore split view']")
    render_patch(view, split_url)
    assert has_element?(view, "#trace-detail button[aria-label='Expand detail']")
    assert has_element?(view, "#trace-list a[href*='second']")
    assert has_element?(view, "#trace-entry-2-0")
    assert activity_payload(view) == original_activity
    assert has_element?(view, "#trace-entry-1-0 .trace-entry-number", "1")
    assert has_element?(view, "#trace-entry-2-0 .trace-entry-number", "2")
    refute_receive {:trace_search, _}
    refute_receive {:trace_activity, _}

    # A fresh LiveView mount represents reloading or opening the shared URL.
    {:ok, reloaded, _} = live(conn, expanded_url)
    render_async(reloaded)
    assert has_element?(reloaded, "#trace-detail button[aria-label='Restore split view']")
    refute has_element?(reloaded, "#trace-list[class~='md:block']")
  end

  test "an expanded URL without a trace does not leak expansion into later selection", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&detail=expanded")
    render_async(view)
    refute has_element?(view, "#trace-detail")
    assert has_element?(view, "#trace-list:not(.hidden)")
    render_click(view, "toggle_list")
    assert has_element?(view, "#trace-list:not(.hidden)")

    view |> element("#trace-list a[href*='first']") |> render_click()
    render_async(view)
    refute Map.has_key?(URI.decode_query(URI.parse(assert_patch(view)).query), "detail")
    assert has_element?(view, "#trace-detail button[aria-label='Expand detail']")
  end

  test "switching references does not reload or change the activity chart", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=first")
    render_async(view)
    assert_receive {:trace_activity, _}
    assert_receive {:trace_search, _}
    original = activity_payload(view)
    view |> element("button", "Load more") |> render_click()
    render_async(view)
    assert_receive {:trace_search, _}

    for reference <- ["second", "first"] do
      view |> element("#trace-list a[href*='#{reference}']") |> render_click()
      assert activity_payload(view) == original
      render_async(view)
      assert activity_payload(view) == original
      assert has_element?(view, "#traces-dashboard-grid[data-hide-on-patch='false']")
      assert has_element?(view, "#trace-detail", reference)
    end

    refute_receive {:trace_activity, _}
    refute_receive {:trace_search, _}
  end

  test "FilterBar switches between trace-enabled sources without a separate heading", %{
    conn: conn,
    database: database,
    organization: organization
  } do
    attrs =
      Map.take(database, [
        :driver,
        :host,
        :port,
        :database_name,
        :username,
        :password,
        :granularities,
        :trace_config
      ])

    {:ok, other} =
      Organizations.create_database_for_org(
        organization,
        Map.put(attrs, :display_name, "Other traces")
      )

    {:ok, stats_only} =
      Organizations.create_database_for_org(
        organization,
        Map.merge(attrs, %{display_name: "Stats only", trace_config: %{}})
      )

    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}")
    render_async(view)
    refute has_element?(view, "#traces-root > header")

    view
    |> element("button[phx-click='toggle_source_dropdown']", "Trace source")
    |> render_click()

    assert has_element?(view, "button[phx-click='select_source'][phx-value-id='#{other.id}']")

    refute has_element?(
             view,
             "button[phx-click='select_source'][phx-value-id='#{stats_only.id}']"
           )

    view
    |> element("button[phx-click='select_source'][phx-value-id='#{other.id}']")
    |> render_click()

    render_async(view)
    assert URI.decode_query(URI.parse(assert_patch(view)).query)["source_id"] == other.id
    assert has_element?(view, "button[phx-click='toggle_source_dropdown']", "Other traces")
  end

  test "activity expands with the same buckets and updates its scope without changing the mailbox",
       %{
         conn: conn,
         database: database
       } do
    {:ok, view, _} =
      live(conn, ~p"/traces?source_id=#{database.id}&reference=first&timeframe=1d&granularity=1h")

    render_async(view)
    assert_receive {:trace_activity, "1h"}
    assert_receive {:trace_search, _}
    render_click(view, "expand_widget", %{"id" => "trace-activity"})
    assert has_element?(view, "#traces-expanded-widget")
    assert has_element?(view, "#traces-root > #traces-expanded-widget")
    refute has_element?(view, ".traces-scrollport #traces-expanded-widget")
    assert length(Floki.find(Floki.parse_document!(render(view)), "#traces-dashboard-grid")) == 1
    assert has_element?(view, "#expanded-widget-trace-activity[phx-hook='ExpandedWidgetView']")
    assert has_element?(view, "#expanded-widget-trace-activity [data-role='table-root']")

    chart = activity_payload(view)
    assert chart["chart_type"] == "bar"
    assert chart["stacked"]
    assert chart["timezone"] == "UTC"
    assert expanded_payload(view) == chart

    assert Enum.find(chart["series"], &(&1["name"] == "jobs/App.Worker · Success"))["data"] == [
             [DateTime.to_unix(~U[2026-09-12 12:00:00Z], :millisecond), 1],
             [DateTime.to_unix(~U[2026-09-12 13:00:00Z], :millisecond), 0]
           ]

    refute_receive {:trace_activity, _}
    refute_receive {:trace_search, _}

    view |> form("#trace-filters", %{path: "jobs", state: "error"}) |> render_submit()
    render_async(view)

    assert has_element?(
             view,
             "#traces-expanded-widget",
             "Activity · jobs (including descendants)"
           )

    assert has_element?(view, "#trace-list", "No traces match")
    assert has_element?(view, "#trace-detail", "first")
    assert expanded_payload(view) == activity_payload(view)

    assert [%{"path" => "jobs/App.Worker", "state" => "error", "color" => "#ef4444"}] =
             expanded_payload(view)["series"]

    refute_receive {:trace_activity, _}

    render_click(view, "close_expanded_widget")
    refute has_element?(view, "#traces-expanded-widget")
    assert has_element?(view, "#trace-detail", "first")
    render_click(view, "expand_widget", %{"id" => "unknown"})
    refute has_element?(view, "#traces-expanded-widget")
  end

  test "compact and expanded activity share a weighted secondary duration line and filters", %{
    conn: conn,
    database: database
  } do
    Application.put_env(:trifle, :trace_activity, FakeDurationActivity)
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&timeframe=1d&granularity=1h")
    render_async(view)
    render_click(view, "expand_widget", %{"id" => "trace-activity"})
    chart = activity_payload(view)
    assert chart == expanded_payload(view)
    assert chart["secondary_y_label"] == "Avg. duration (ms)"
    line = Enum.find(chart["series"], &(&1["y_axis"] == "secondary"))
    assert line["chart_type"] == "line"
    assert line["stacked"] == false
    assert line["color"] == "#8b5cf6"
    assert line["unit"] == "ms"
    assert Enum.map(line["data"], &List.last/1) == [440.0, 500.0]
    assert length(Enum.filter(chart["series"], &(&1["y_axis"] == "secondary"))) == 1

    view |> form("#trace-filters", %{path: "jobs", state: "warning"}) |> render_submit()
    render_async(view)
    chart = activity_payload(view)
    assert chart == expanded_payload(view)

    assert [%{"state" => "warning"}, %{"y_axis" => "secondary", "data" => [[_, 900.0], [_, nil]]}] =
             chart["series"]

    view |> form("#trace-filters", %{path: "jobs", state: "running"}) |> render_submit()
    render_async(view)
    assert activity_payload(view)["series"] == []
  end

  test "expanded activity safely shows a path with no counters", %{conn: conn, database: database} do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&path=missing%2Fpath")
    render_async(view)
    render_click(view, "expand_widget", %{"id" => "trace-activity"})
    assert expanded_payload(view)["series"] == []
    assert render(view) =~ "No recorded activity for this path, state and timeframe."
    assert has_element?(view, "#traces-expanded-widget", "Activity · missing/path")
  end

  test "path and state scope both surfaces without refetching Stats", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&timeframe=1d&granularity=1h")
    render_async(view)
    assert_receive {:trace_activity, "1h"}
    assert_receive {:trace_search, _}
    view |> form("#trace-filters", %{path: "jobs", state: "error"}) |> render_submit()
    html = render_async(view)
    assert html =~ "Activity · jobs (including descendants)"
    assert activity_total(view) == 1
    assert html =~ "No traces match"
    assert_receive {:trace_search, filters}
    assert filters[:segment] == "jobs"
    assert filters[:state] == "error"
    refute_receive {:trace_activity, _}
  end

  test "stale detail results cannot replace a newer selection", %{conn: conn, database: database} do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=slow")
    assert_receive {:slow_detail, pid}, 1000
    view |> form("#trace-reference", %{reference: "first"}) |> render_submit()
    send(pid, :finish)
    html = render_async(view)
    assert html =~ "&lt;script&gt;part 1"
    assert has_element?(view, "#trace-list a[aria-current='true'][href*='first']")
    refute has_element?(view, "#trace-detail", "slow")
  end

  test "state colors and scoped totals persist across state and path filtering; tags only filter the list",
       %{conn: conn, database: database} do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}")
    render_async(view)
    assert_receive {:trace_activity, _}

    colors = %{
      "success" => "#14b8a6",
      "warning" => "#f97316",
      "error" => "#ef4444",
      "running" => "#3b82f6"
    }

    all = activity_payload(view)
    assert length(all["series"]) == 4

    for series <- all["series"] do
      assert series["color"] == colors[series["state"]]
      assert series["legend_name"] == series["path"]
    end

    view |> form("#trace-filters", %{state: "warning"}) |> render_submit()
    render_async(view)
    assert [%{"state" => "warning", "color" => "#f97316"}] = activity_payload(view)["series"]
    view |> form("#trace-filters", %{state: "warning", tags: "queue:default"}) |> render_submit()
    render_async(view)
    assert [%{"state" => "warning", "color" => "#f97316"}] = activity_payload(view)["series"]

    view |> form("#trace-filters", %{path: "requests", state: "warning"}) |> render_submit()
    render_async(view)
    assert activity_payload(view)["series"] == []
    view |> form("#trace-filters", %{path: "requests", state: "running"}) |> render_submit()
    render_async(view)
    assert activity_total(view) == 3

    assert [%{"path" => "requests/get", "state" => "running", "color" => "#3b82f6"}] =
             activity_payload(view)["series"]

    view |> form("#trace-filters", %{path: "", state: ""}) |> render_submit()
    render_async(view)
    assert activity_payload(view) == all
    refute_receive {:trace_activity, _}
  end

  test "manual refresh reloads activity and selected detail; pause fixes the range", %{
    conn: conn,
    database: database
  } do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{database.id}&reference=first")
    render_async(view)
    assert_receive {:trace_activity, _}
    view |> element("button[aria-label='Refresh']") |> render_click()
    render_async(view)
    assert_receive {:trace_activity, _}
    view |> element("button[aria-label='Pause']") |> render_click()
    render_async(view)
    path = assert_patch(view)
    assert URI.decode_query(URI.parse(path).query)["from"]
    assert URI.decode_query(URI.parse(path).query)["to"]
  end

  test "inaccessible sources and invalid params never start reads", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/traces?source_id=#{Ecto.UUID.generate()}")
    assert render_async(view) =~ "Choose an active database"
    refute_receive {:trace_search, _}
    refute_receive {:trace_activity, _}
    render_click(view, "expand_widget", %{"id" => "trace-activity"})
    refute has_element?(view, "#traces-expanded-widget")
  end

  defp activity_total(view) do
    activity_payload(view)["series"]
    |> Enum.flat_map(& &1["data"])
    |> Enum.map(&List.last/1)
    |> Enum.sum()
  end

  defp activity_payload(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.attribute("#traces-dashboard-grid-widget-data-trace-activity", "data-widget-payload")
    |> hd()
    |> Jason.decode!()
    |> Map.fetch!("payload")
  end

  defp expanded_payload(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.attribute("#expanded-widget-trace-activity", "data-chart")
    |> hd()
    |> Jason.decode!()
  end
end
