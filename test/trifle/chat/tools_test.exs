defmodule Trifle.Chat.ToolsTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.Tools
  alias Trifle.Stats.Series
  alias Trifle.Stats.Source

  defmodule FakeSourceRecord do
    defstruct []
  end

  defmodule FakeSource do
    @behaviour Source.Behaviour

    def type(_record), do: :database
    def id(_record), do: "fake-source"
    def organization_id(_record), do: "org-1"
    def display_name(_record), do: "Fake Source"
    def stats_config(_record), do: %{time_zone: "UTC"}
    def default_timeframe(_record), do: "24h"
    def default_granularity(_record), do: "1h"
    def available_granularities(_record), do: ["1m", "1h", "1d"]
    def time_zone(_record), do: "UTC"
    def transponders(_record), do: []
  end

  defmodule CoarseOnlySource do
    @behaviour Source.Behaviour

    def type(_record), do: :database
    def id(_record), do: "coarse-only-source"
    def organization_id(_record), do: "org-1"
    def display_name(_record), do: "Coarse Only Source"
    def stats_config(_record), do: %{time_zone: "UTC"}
    def default_timeframe(_record), do: "24h"
    def default_granularity(_record), do: "1d"
    def available_granularities(_record), do: ["1d"]
    def time_zone(_record), do: "UTC"
    def transponders(_record), do: []
  end

  describe "__tabularize_for_test__/2" do
    test "returns columns and rows sorted chronologically" do
      series = series_fixture()

      assert %{"columns" => ["at", "data.orders", "data.revenue"], "rows" => rows} =
               Tools.__tabularize_for_test__(series)

      assert rows == [
               ["2024-01-01T00:00:00Z", 5, 12],
               ["2024-01-02T00:00:00Z", 7, nil]
             ]
    end

    test "filters columns when only_paths provided" do
      series = series_fixture()

      assert %{"columns" => ["at", "data.revenue"], "rows" => rows} =
               Tools.__tabularize_for_test__(series, only_paths: ["data.revenue"])

      assert rows == [
               ["2024-01-01T00:00:00Z", 12],
               ["2024-01-02T00:00:00Z", nil]
             ]
    end
  end

  describe "__subset_table_for_test__/2" do
    test "extracts requested paths and preserves timestamps" do
      table = Tools.__tabularize_for_test__(series_fixture())

      assert %{"columns" => ["at", "data.orders"], "rows" => rows} =
               Tools.__subset_table_for_test__(table, ["data.orders"])

      assert rows == [
               ["2024-01-01T00:00:00Z", 5],
               ["2024-01-02T00:00:00Z", 7]
             ]
    end

    test "returns nil when no matching columns found" do
      table = Tools.__tabularize_for_test__(series_fixture())

      assert Tools.__subset_table_for_test__(table, ["missing.path"]) == nil
    end
  end

  describe "describe_dashboard_widgets" do
    test "returns the widget spec and prompt fragment" do
      assert {:ok, %{status: "ok", widget_spec: spec, prompt_fragment: prompt}} =
               Tools.execute("describe_dashboard_widgets", "{}", %{})

      widget_types =
        spec.widgets
        |> Enum.map(& &1["type"])

      assert "kpi" in widget_types
      assert "heatmap" in widget_types
      assert prompt =~ "build_metric_dashboard"
    end
  end

  describe "definitions/1" do
    test "includes the metric schema inspection tool and keeps key discovery argument-free" do
      definitions = Tools.definitions(%{})

      tool_names =
        definitions
        |> Enum.map(&get_in(&1, ["function", "name"]))

      list_available_metrics =
        Enum.find(definitions, &(get_in(&1, ["function", "name"]) == "list_available_metrics"))

      inspect_metric_schema =
        Enum.find(definitions, &(get_in(&1, ["function", "name"]) == "inspect_metric_schema"))

      assert "inspect_metric_schema" in tool_names
      assert get_in(list_available_metrics, ["function", "parameters", "properties"]) == %{}

      assert get_in(inspect_metric_schema, ["function", "parameters", "required"]) == [
               "metric_key"
             ]

      assert get_in(list_available_metrics, ["function", "description"]) =~
               "single coarse sample bucket"

      assert get_in(
               Enum.find(
                 definitions,
                 &(get_in(&1, ["function", "name"]) == "build_metric_dashboard")
               ),
               ["function", "description"]
             ) =~
               "chat point limit"
    end
  end

  describe "system_prompt/1" do
    test "steers structure discovery to schema inspection and visual requests to dashboards" do
      prompt = Tools.system_prompt(%{})

      refute prompt =~ "format_metric_timeline"
      refute prompt =~ "format_metric_category"
      assert prompt =~ "inspect_metric_schema"
      assert prompt =~ "skip `list_available_metrics`"
      assert prompt =~ "Do not use `fetch_metric_timeseries` just"
      assert prompt =~ "discover structure or tracked paths"
      assert prompt =~ "When the user asks for any visual output"
      assert prompt =~ "single-widget dashboard"
      assert prompt =~ "use category widgets only"
      assert prompt =~ "must set"
      assert prompt =~ "`chart_type` explicitly"
      assert prompt =~ "Do not use distribution widgets for pies"
      assert prompt =~ "`chart` and `style` are invalid"
      assert prompt =~ "must not contain wildcard"
      assert prompt =~ "dashboard widget configs passed to `build_metric_dashboard`"
      assert prompt =~ "hard-capped at 1000 points"
    end
  end

  describe "compact_tool_payload_for_model/2" do
    test "omits dashboard series snapshots and keeps widget summaries" do
      payload = %{
        "status" => "ok",
        "metric_key" => "sales",
        "visualization" => %{
          "id" => "dash-1",
          "title" => "Sales Overview",
          "timeframe" => %{"label" => "90d", "granularity" => "1d"},
          "series_snapshot" => %{
            "at" => ["2024-01-01T00:00:00Z"],
            "values" => [%{"revenue" => 12}]
          },
          "dashboard" => %{
            "payload" => %{
              "grid" => [
                %{
                  "id" => "widget-1",
                  "type" => "category",
                  "title" => "Revenue",
                  "chart_type" => "pie",
                  "series" => [
                    %{
                      "kind" => "path",
                      "path" => "revenue",
                      "visible" => true
                    }
                  ],
                  "x" => 0,
                  "y" => 0,
                  "w" => 3,
                  "h" => 2
                }
              ]
            }
          }
        }
      }

      compact = Tools.compact_tool_payload_for_model("build_metric_dashboard", payload)

      assert compact.status == "ok"
      assert compact.metric_key == "sales"
      assert compact.visualization.widget_count == 1

      assert [
               %{
                 id: "widget-1",
                 type: "category",
                 chart_type: "pie",
                 series: [%{kind: "path", path: "revenue", visible: true}]
               }
             ] =
               compact.visualization.widgets

      refute Map.has_key?(compact.visualization, :series_snapshot)
    end

    test "caps timeseries previews and drops duplicated table output" do
      payload = %{
        "status" => "ok",
        "metric_key" => "sales",
        "timeframe" => %{"label" => "90d", "granularity" => "1d"},
        "timeline" =>
          for day <- 1..35 do
            %{
              "at" => "2024-01-#{String.pad_leading(Integer.to_string(day), 2, "0")}T00:00:00Z",
              "data" => %{"revenue" => day}
            }
          end,
        "summary" => for(idx <- 1..30, do: %{"path" => "metric.#{idx}", "latest" => idx}),
        "available_paths" => for(idx <- 1..75, do: "metric.#{idx}"),
        "table" => %{"columns" => ["at"], "rows" => []}
      }

      compact = Tools.compact_tool_payload_for_model("fetch_metric_timeseries", payload)

      assert compact.point_count == 35
      assert compact.timeline_truncated
      assert length(compact.timeline_preview) <= 30
      assert compact.summary_truncated
      assert compact.available_paths_truncated
      refute Map.has_key?(compact, :table)
    end
  end

  describe "schema helpers" do
    test "picks the coarsest supported granularity by duration" do
      assert Tools.__pick_coarsest_granularity_for_test__(["1m", "1h", "1d", "1mo"]) == "1mo"
    end

    test "schema timeframe spans a single bucket at the coarsest granularity" do
      now = ~U[2024-01-02 00:00:00Z]

      {from, to, label} =
        Tools.__resolve_schema_timeframe_for_test__("UTC", "1d", now)

      assert label == "schema sample"
      assert DateTime.diff(to, from, :second) == 24 * 60 * 60
      assert DateTime.compare(to, now) == :eq
    end

    test "widens chat fetch granularity when the requested one would exceed the point limit" do
      source = Source.new(FakeSource, %FakeSourceRecord{})
      from = ~U[2024-01-01 00:00:00Z]
      to = ~U[2024-03-01 00:00:00Z]

      assert {:ok, {"1d", "1m"}} =
               Tools.__adjust_chat_fetch_granularity_for_test__(source, "1m", from, to)
    end

    test "returns an error when no supported granularity can fit within the chat point limit" do
      source = Source.new(CoarseOnlySource, %FakeSourceRecord{})
      from = ~U[2020-01-01 00:00:00Z]
      to = ~U[2024-01-01 00:00:00Z]

      assert {:error, %{error: error, point_limit: point_limit, suggested_granularity: "1d"}} =
               Tools.__adjust_chat_fetch_granularity_for_test__(source, "1d", from, to)

      assert point_limit == Tools.__chat_point_limit_for_test__()
      assert error =~ "chat limit"
    end

    test "builds a schema payload from a single sampled point" do
      from = ~U[2024-01-01 00:00:00Z]
      to = ~U[2024-01-02 00:00:00Z]

      assert {:ok, payload} =
               Tools.__build_schema_payload_for_test__(
                 "sales",
                 series_fixture(),
                 "1d",
                 from,
                 to
               )

      assert payload.status == "ok"
      assert payload.metric_key == "sales"
      assert payload.path_count == 2
      assert payload.paths == ["data.orders", "data.revenue"]
      assert payload.timeframe.label == "schema_sample"
      assert payload.sample_point.at == "2024-01-02T00:00:00Z"
    end

    test "accepts common nested dashboard grid shapes" do
      assert {:ok, [%{"type" => "kpi", "title" => "Revenue"}]} =
               Tools.__require_grid_for_test__(%{
                 "grid" => %{
                   "payload" => %{
                     "grid" => [
                       %{"type" => "kpi", "title" => "Revenue"}
                     ]
                   }
                 }
               })

      assert {:ok, [%{"type" => "timeseries", "title" => "Trend"}]} =
               Tools.__require_grid_for_test__(%{
                 "grid" => %{"type" => "timeseries", "title" => "Trend"}
               })
    end
  end

  defp series_fixture do
    timestamps = [
      ~U[2024-01-01 00:00:00Z],
      ~U[2024-01-02 00:00:00Z]
    ]

    values = [
      %{
        "data" => %{
          "orders" => 5,
          "revenue" => 12
        }
      },
      %{
        "data" => %{
          "orders" => 7
        }
      }
    ]

    Series.new(%{at: timestamps, values: values})
  end
end
