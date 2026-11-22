defmodule Trifle.Chat.TraceActivityTest do
  use Trifle.DataCase

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Chat.Tools
  alias Trifle.MetricsMock
  alias Trifle.Organizations.OrganizationMembership
  alias Trifle.Stats.Source

  setup do
    previous_metrics = Application.fetch_env(:trifle, :metrics_module)
    Application.put_env(:trifle, :metrics_module, MetricsMock)
    start_supervised!(MetricsMock)

    on_exit(fn ->
      case previous_metrics do
        {:ok, module} -> Application.put_env(:trifle, :metrics_module, module)
        :error -> Application.delete_env(:trifle, :metrics_module)
      end
    end)

    org = organization_fixture()
    app_entitlement_fixture(org)
    database = trace_database(org, "Job traces")

    active_source =
      database_fixture(%{
        organization: org,
        display_name: "General analytics",
        driver: "sqlite",
        file_path: "/tmp/baker-general-analytics.sqlite"
      })
      |> Source.from_database()

    %{
      org: org,
      database: database,
      context: %{
        membership: %OrganizationMembership{organization_id: org.id},
        source: active_source
      }
    }
  end

  test "ranks failures from the requested Stats range and reports totals across matching paths",
       %{database: database, context: context} do
    test_pid = self()

    MetricsMock.stub_fetch_series(fn source, key, from, to, granularity, opts ->
      send(test_pid, {:stats_query, Source.id(source), key, from, to, granularity, opts})
      at = [from, DateTime.add(from, 1, :hour)]

      values =
        case key do
          "__system__key__" ->
            [
              %{"keys" => %{"jobs/calc/worker" => 10, "jobs/calculation" => 200}},
              %{"keys" => %{"jobs/calc/worker" => 4, "jobs/calc/export" => 3}}
            ]

          "jobs/calc/worker" ->
            [
              %{
                "count" => 10,
                "states" => %{"error" => 5, "success" => 5},
                "duration" => %{"count" => 2, "sum" => 900}
              },
              %{"count" => 4, "duration" => %{"count" => 1, "sum" => 600}}
            ]

          "jobs/calc/export" ->
            [%{}, %{"count" => 3, "states" => %{"error" => 3}}]
        end

      {:ok, %{series: Trifle.Stats.series(%{at: at, values: values})}}
    end)

    filters = %{timeframe: "24h", granularity: "1h", path: "jobs/calc", limit: 1}
    source_id = database.id

    assert {:ok,
            %{
              trace_source: %{id: ^source_id, display_name: "Job traces"},
              timeframe: %{label: "24h", granularity: "1h"},
              sort_by: :error_count,
              path_count: 2,
              paths: [
                %{
                  path: "jobs/calc/worker",
                  states: %{"error" => 5, "success" => 5, "unclassified" => 4},
                  error_count: 5,
                  error_rate_pct: 50.0,
                  classified_count: 10,
                  count: 14,
                  average_duration_ms: 500.0
                }
              ],
              totals: %{count: 17, error_count: 8, classified_count: 13}
            } = result} = run_tool("summarize_trace_activity", filters, context)

    for key <- ["__system__key__", "jobs/calc/worker", "jobs/calc/export"] do
      assert_received {:stats_query, ^source_id, ^key, from, to, "1h", opts}
      assert DateTime.diff(to, from, :hour) == 24
      assert opts[:transponders] == :none
    end

    assert MetricsMock.calls().fetch_series == 3

    assert %{"paths" => [%{"error_count" => 5}], "trace_source" => %{"id" => ^source_id}} =
             Tools.compact_tool_payload_for_model(
               "summarize_trace_activity",
               Jason.encode!(result)
             )

    assert {:ok, %{paths: [%{path: "jobs/calc/export", error_rate_pct: 100.0}]}} =
             run_tool(
               "summarize_trace_activity",
               Map.put(filters, :sort_by, "error_rate_pct"),
               context
             )
  end

  test "uses the explicitly selected trace database for exact-path metric tools",
       %{org: org, context: context} do
    database = trace_database(org, "Shipping traces")
    id = database.id
    test_pid = self()

    MetricsMock.stub_fetch_series(fn source, key, from, to, granularity, opts ->
      send(test_pid, {:stats_query, Source.id(source), key, from, to, granularity, opts})

      samples =
        if key == "__system__key__",
          do: [%{"keys" => %{"jobs/ship" => 3}}],
          else: [%{"count" => 3, "states" => %{"success" => 1, "error" => 2}}]

      {:ok, %{series: Trifle.Stats.series(%{at: [from], values: samples})}}
    end)

    scope = %{scope: "traces", source_id: id}
    query = Map.merge(scope, %{metric_key: "jobs/ship", timeframe: "24h", granularity: "1h"})

    assert {:ok, %{paths: [%{metric_key: "jobs/ship"}], trace_source: %{id: ^id}}} =
             run_tool("list_available_metrics", scope, context)

    assert {:ok, %{paths: paths, trace_source: %{id: ^id}}} =
             run_tool("inspect_metric_schema", Map.put(scope, :metric_key, "jobs/ship"), context)

    assert "states.error" in paths

    assert {:ok, %{metric_key: "jobs/ship", trace_source: %{id: ^id}}} =
             run_tool("fetch_metric_timeseries", query, context)

    assert {:ok, %{value: 2.0, trace_source: %{id: ^id}} = result} =
             run_tool(
               "aggregate_metric_series",
               Map.merge(query, %{value_path: "states.error", aggregator: "sum"}),
               context
             )

    assert %{value: 2.0, trace_source: %{"id" => ^id}} =
             Tools.compact_tool_payload_for_model(
               "aggregate_metric_series",
               Jason.encode!(result)
             )

    for key <- ["__system__key__", "jobs/ship", "jobs/ship", "jobs/ship"] do
      assert_received {:stats_query, ^id, ^key, _, _, _, opts}
      assert opts[:transponders] == :none
    end

    assert {:error, %{error: "Choose a source_id from list_trace_sources."}} =
             run_tool("summarize_trace_activity", %{timeframe: "24h"}, context)
  end

  test "rejects a trace database outside the workspace before fetching Stats",
       %{context: context} do
    foreign_org = organization_fixture(%{name: "Another organization", slug: "another-org"})
    app_entitlement_fixture(foreign_org)
    foreign_database = trace_database(foreign_org, "Private traces")
    scope = %{source_id: foreign_database.id, scope: "traces"}

    assert {:error, %{error: "This trace source is unavailable."}} =
             run_tool("summarize_trace_activity", scope, context)

    assert {:error, %{error: "This trace source is unavailable."}} =
             run_tool(
               "fetch_metric_timeseries",
               Map.put(scope, :metric_key, "jobs/ship"),
               context
             )

    assert MetricsMock.calls().fetch_series == 0
  end

  defp run_tool(tool, args, context), do: Tools.execute(tool, Jason.encode!(args), context)

  defp trace_database(org, name) do
    database_fixture(%{
      organization: org,
      display_name: name,
      driver: "postgres",
      host: "postgres",
      port: 5432,
      database_name: "test",
      username: "test",
      password: "test",
      default_timeframe: "24h",
      default_granularity: "1h",
      granularities: ["1h", "1d"],
      trace_config: %{
        "index_name" => "trace_activity_test",
        "data_driver" => "file",
        "data_path" => "/tmp/traces",
        "retention_days" => 7,
        "gzip" => false
      }
    })
  end
end
