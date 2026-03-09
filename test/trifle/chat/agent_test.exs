defmodule Trifle.Chat.AgentTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat.Agent
  alias Trifle.Chat.Session

  test "build_messages compacts dashboard tool payloads before sending them back to OpenAI" do
    tool_payload = %{
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
              %{"id" => "widget-1", "type" => "kpi", "title" => "Revenue", "path" => "revenue", "x" => 0, "y" => 0, "w" => 3, "h" => 2}
            ]
          }
        }
      }
    }

    session = %Session{
      id: "session-1",
      user_id: "user-1",
      organization_id: "org-1",
      source: %{"type" => "database", "id" => "db-1"},
      messages: [
        %{
          role: "assistant",
          tool_calls: [
            %{id: "call-1", type: "function", function: %{name: "build_metric_dashboard", arguments: "{}"}}
          ]
        },
        %{
          role: "tool",
          tool_call_id: "call-1",
          name: "build_metric_dashboard",
          content: Jason.encode!(tool_payload)
        }
      ]
    }

    [system_message, assistant_message, tool_message] = Agent.__build_messages_for_test__(session, %{})

    assert system_message["role"] == "system"
    assert assistant_message["role"] == "assistant"
    assert tool_message["role"] == "tool"

    compact = Jason.decode!(tool_message["content"])

    assert compact["status"] == "ok"
    assert compact["metric_key"] == "sales"
    assert compact["visualization"]["widget_count"] == 1
    refute Map.has_key?(compact["visualization"], "series_snapshot")
  end

  test "too many iterations returns a user-facing error map" do
    error = Agent.__too_many_iterations_error_for_test__()

    assert error.status == :too_many_iterations
    assert error.message =~ "retry limit"
  end
end
