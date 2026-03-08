defmodule Trifle.Chat.RenderableMessagesTest do
  use ExUnit.Case, async: true

  alias Trifle.Chat
  alias Trifle.Chat.Session

  test "prefers embedded assistant visualizations over trailing tool fallback" do
    visualization = %{
      "id" => "dash-1",
      "type" => "dashboard",
      "title" => "Ops Overview",
      "dashboard" => %{"id" => "dash-1", "name" => "Ops Overview", "payload" => %{"grid" => []}},
      "series_snapshot" => %{"at" => ["2024-01-01T00:00:00Z"], "values" => [%{}]}
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
          content: Jason.encode!(%{"visualization" => visualization})
        },
        %{
          role: "assistant",
          content: "Here is the dashboard.",
          visualizations: [visualization]
        }
      ]
    }

    assert [%{role: "assistant", visualizations: visualizations}] = Chat.renderable_messages(session)
    assert length(visualizations) == 1
    assert hd(visualizations).type == "dashboard"
  end

  test "falls back to tool-generated dashboards when assistant message does not embed them" do
    visualization = %{
      "id" => "dash-2",
      "type" => "dashboard",
      "title" => "API Calls Overview",
      "dashboard" => %{
        "id" => "dash-2",
        "name" => "API Calls Overview",
        "payload" => %{"grid" => [%{"id" => "widget-1", "type" => "timeseries"}]}
      },
      "series_snapshot" => %{"at" => ["2024-01-01T00:00:00Z"], "values" => [%{"total" => 5}]}
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
          content: Jason.encode!(%{"visualization" => visualization})
        },
        %{
          role: "assistant",
          content: "The trend is moving up."
        }
      ]
    }

    assert [%{role: "assistant", visualizations: visualizations}] = Chat.renderable_messages(session)
    assert length(visualizations) == 1
    assert hd(visualizations).type == "dashboard"
  end
end
