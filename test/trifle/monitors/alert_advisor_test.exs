defmodule Trifle.Monitors.AlertAdvisorTest do
  use ExUnit.Case, async: true

  alias Trifle.Monitors.AlertAdvisor
  alias Trifle.Monitors.Monitor
  alias Trifle.Stats.Series

  test "recommend merges points from all resolved final targets" do
    stats = build_series()

    monitor = %Monitor{
      id: "monitor-1",
      name: "Latency guard",
      alert_metric_key: "latency.p95",
      alert_timeframe: "12h",
      alert_granularity: "1h",
      alert_series: [
        %{"kind" => "path", "path" => "incoming.*", "visible" => false},
        %{"kind" => "path", "path" => "outgoing.*", "visible" => false},
        %{"kind" => "expression", "expression" => "a - b", "visible" => true}
      ]
    }

    test_pid = self()

    client = fn messages, _opts ->
      send(test_pid, {:advisor_messages, messages})

      {:ok,
       %{
         "choices" => [
           %{
             "message" => %{
               "content" =>
                 Jason.encode!(%{
                   "settings" => %{
                     "threshold_value" => 10.0,
                     "threshold_direction" => "above"
                   },
                   "explanation" => "Use a threshold above the recent range."
                 })
             }
           }
         ]
       }}
    end

    assert {:ok, %{strategy: :threshold, variant: :balanced}} =
             AlertAdvisor.recommend(
               monitor,
               stats,
               strategy: :threshold,
               client: client,
               max_points: 4
             )

    assert_received {:advisor_messages, messages}

    payload =
      messages
      |> Enum.find(&(&1["role"] == "user"))
      |> Map.fetch!("content")
      |> extract_payload()

    assert payload["monitor"]["metric_path"] == "a - b"
    assert length(payload["recent_values"]) == 4
    assert Enum.member?(payload["recent_values"], 14.0)
  end

  test "recommend unwraps legacy fallback series points" do
    stats = build_series()

    monitor = %Monitor{
      id: "monitor-legacy",
      name: "Legacy guard",
      alert_metric_key: "latency.p95",
      alert_metric_path: "incoming.a",
      alert_timeframe: "12h",
      alert_granularity: "1h",
      alert_series: [%{"kind" => "path", "path" => "", "visible" => true}]
    }

    test_pid = self()

    client = fn messages, _opts ->
      send(test_pid, {:legacy_advisor_messages, messages})

      {:ok,
       %{
         "choices" => [
           %{
             "message" => %{
               "content" =>
                 Jason.encode!(%{
                   "settings" => %{
                     "threshold_value" => 10.0,
                     "threshold_direction" => "above"
                   },
                   "explanation" => "Use the current level as the baseline."
                 })
             }
           }
         ]
       }}
    end

    assert {:ok, %{strategy: :threshold}} =
             AlertAdvisor.recommend(
               monitor,
               stats,
               strategy: :threshold,
               client: client,
               max_points: 3
             )

    assert_received {:legacy_advisor_messages, messages}

    payload =
      messages
      |> Enum.find(&(&1["role"] == "user"))
      |> Map.fetch!("content")
      |> extract_payload()

    assert payload["monitor"]["metric_path"] == "incoming.a"
    assert payload["recent_values"] == [10.0, 12.0, 15.0]
  end

  defp extract_payload(content) do
    content
    |> extract_json_object()
    |> Jason.decode!()
  end

  defp extract_json_object(content) when is_binary(content) do
    start_index =
      case :binary.match(content, "{") do
        {index, 1} -> index
        :nomatch -> raise ArgumentError, "no JSON object found in payload"
      end

    do_extract_json_object(content, start_index, start_index, 0, false, false)
  end

  defp do_extract_json_object(content, start_index, index, depth, in_string?, escaped?)
       when index < byte_size(content) do
    char = :binary.at(content, index)

    cond do
      in_string? and escaped? ->
        do_extract_json_object(content, start_index, index + 1, depth, true, false)

      in_string? and char == ?\\ ->
        do_extract_json_object(content, start_index, index + 1, depth, true, true)

      in_string? and char == ?" ->
        do_extract_json_object(content, start_index, index + 1, depth, false, false)

      in_string? ->
        do_extract_json_object(content, start_index, index + 1, depth, true, false)

      char == ?" ->
        do_extract_json_object(content, start_index, index + 1, depth, true, false)

      char == ?{ ->
        do_extract_json_object(content, start_index, index + 1, depth + 1, false, false)

      char == ?} and depth == 1 ->
        byte_size = index - start_index + 1
        binary_part(content, start_index, byte_size)

      char == ?} ->
        do_extract_json_object(content, start_index, index + 1, depth - 1, false, false)

      true ->
        do_extract_json_object(content, start_index, index + 1, depth, false, false)
    end
  end

  defp do_extract_json_object(_content, _start_index, _index, _depth, _in_string?, _escaped?) do
    raise ArgumentError, "unterminated JSON object in payload"
  end

  defp build_series do
    base_time = ~U[2025-01-01 00:00:00Z]

    raw = %{
      at: [
        base_time,
        DateTime.add(base_time, 60, :second),
        DateTime.add(base_time, 120, :second)
      ],
      values: [
        %{
          "incoming" => %{"a" => 10.0, "b" => 16.0},
          "outgoing" => %{"a" => 3.0, "b" => 4.0}
        },
        %{
          "incoming" => %{"a" => 12.0, "b" => 18.0},
          "outgoing" => %{"a" => 5.0, "b" => 6.0}
        },
        %{
          "incoming" => %{"a" => 15.0, "b" => 22.0},
          "outgoing" => %{"a" => 7.0, "b" => 8.0}
        }
      ]
    }

    Series.new(raw)
  end
end
