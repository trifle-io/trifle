defmodule Trifle.Traces.ActivityTest do
  use ExUnit.Case, async: true
  alias Trifle.Traces.Activity

  for days <- [1, 2, 3, 7] do
    test "#{days}d hourly activity preserves buckets and aggregates full keys once" do
      hours = unquote(days) * 24
      at = for n <- 0..(hours - 1), do: DateTime.add(~U[2026-09-01 00:00:00Z], n, :hour)

      keys = %{
        "jobs" => 1,
        "jobs/App.Worker" => 2,
        "jobs/deep/test*rb" => 3,
        "jobs-other/Worker" => 4,
        "requests" => 5,
        "jobs::Old.Worker" => 6
      }

      values = for n <- 0..(hours - 1), do: if(rem(n, 2) == 0, do: %{"keys" => keys}, else: %{})

      input = %{
        catalog: Trifle.Stats.series(%{at: at, values: values}),
        metrics:
          Map.new(keys, fn {key, _} ->
            {key,
             %{
               at: at,
               values:
                 Enum.map(values, fn value ->
                   %{"states" => %{"success" => get_in(value, ["keys", key]) || 0}}
                 end)
             }}
          end)
      }

      result = Activity.build(input, "jobs")
      assert result.total == div(hours, 2) * 6

      assert Enum.map(result.series, & &1.path) == [
               "jobs",
               "jobs/App.Worker",
               "jobs/deep/test*rb"
             ]

      assert Enum.all?(result.series, &(length(&1.data) == hours))

      assert Enum.map(hd(result.series).data, &hd/1) ==
               Enum.map(at, &DateTime.to_unix(&1, :millisecond))

      assert Enum.at(hd(result.series).data, 1) |> List.last() == 0
      assert Activity.build(input).total == div(hours, 2) * 21
      assert Activity.build(input, "jobs/deep").total == div(hours, 2) * 3
      assert Activity.build(input, "jobs::Old.Worker").total == div(hours, 2) * 6
    end
  end

  test "path segments preserve dots, stars, backslashes, percent sequences and Unicode" do
    keys = ["jobs/test.rb", "jobs/*", "jobs/file\\name", "jobs/test%2Erb", "jobs/東京.rb"]
    at = [~U[2026-09-01 00:00:00Z]]

    input = %{
      catalog: %{at: at, values: [%{"keys" => Map.new(keys, &{&1, 1})}]},
      metrics: Map.new(keys, &{&1, %{at: at, values: [%{"states" => %{"warning" => 1}}]}})
    }

    for key <- keys do
      assert %{total: 1, series: [%{path: ^key, legend_name: ^key, state: "warning"}]} =
               Activity.build(input, key)
    end

    assert Activity.build(input, "jobs").total == 5
    assert Activity.paths(keys) == Enum.sort(["jobs" | keys])
  end

  test "missing data is not replaced with a synthetic bar" do
    assert Activity.build(nil) == %{series: [], total: 0, paths: []}

    assert %{series: [], total: 0} =
             Activity.build(%{catalog: %{values: [%{"keys" => %{"jobs/a" => 9}}]}})
  end

  test "state stacks reconcile with counts, keep path boundaries and align sparse buckets by timestamp" do
    at = [~U[2026-09-01 00:00:00Z], ~U[2026-09-01 01:00:00Z]]

    input = %{
      catalog: %{
        at: at,
        values: [
          %{
            "keys" => %{
              "jobs/App.Worker" => 6,
              "jobs/deep/test.rb" => 2,
              "jobs-other/Worker" => 7
            }
          },
          %{"keys" => %{"jobs/App.Worker" => 2}}
        ]
      },
      metrics: %{
        "jobs/App.Worker" =>
          Trifle.Stats.series(%{
            at: Enum.reverse(at),
            values: [
              %{"count" => 2, "states" => %{"warning" => 2}},
              %{
                "count" => 6,
                "states" => %{"success" => 2, "warning" => 1, "error" => 1, "running" => 1}
              }
            ]
          }),
        "jobs/deep/test.rb" => %{
          at: [hd(at)],
          values: [%{"count" => 2, "states" => %{"success" => Decimal.new(2)}}]
        },
        "jobs-other/Worker" => %{
          at: [hd(at)],
          values: [%{"count" => 7, "states" => %{"success" => 7}}]
        }
      }
    }

    all = Activity.build(input)
    jobs = Activity.build(input, "jobs")
    warnings = Activity.build(input, "jobs", "warning")
    assert all.total == 17
    assert jobs.total == 10
    assert warnings.total == 3
    assert warnings.paths == all.paths

    assert [%{path: "jobs/App.Worker", state: "warning", data: [[_, 1], [_, 2]]}] =
             warnings.series

    assert Activity.build(input, "jobs", "running").total == 1
    assert Activity.build(input, "jobs", "error").total == 1
    assert Activity.build(input, "jobs/deep", "success").total == 2
    assert Activity.build(input, "jobs/deep", "warning").series == []

    assert Enum.map(jobs.series, & &1.state) == [
             "success",
             "success",
             "warning",
             "error",
             "running",
             "unclassified"
           ]

    assert length(Enum.uniq_by(jobs.series, & &1.id)) == length(jobs.series)
  end

  test "average duration combines samples by count, follows path/state filters and leaves missing buckets blank" do
    at = [~U[2026-09-01 00:00:00Z], ~U[2026-09-01 01:00:00Z], ~U[2026-09-01 02:00:00Z]]

    input = %{
      catalog: %{
        at: at,
        values: [%{"keys" => %{"jobs/A" => 12, "jobs/B" => 1, "jobs-other/C" => 1}}, %{}, %{}]
      },
      metrics: %{
        "jobs/A" => %{
          at: at,
          values: [
            %{
              "count" => 12,
              "states" => %{"success" => 11, "warning" => 1},
              "duration" => %{
                "count" => Decimal.new(10),
                "sum" => Decimal.new(1000),
                "states" => %{
                  "success" => %{"count" => 9, "sum" => 900},
                  "warning" => %{"count" => 1, "sum" => 100}
                }
              }
            },
            %{
              "count" => 1,
              "states" => %{"success" => 1},
              "duration" => %{
                "count" => 1,
                "sum" => 0,
                "states" => %{"success" => %{"count" => 1, "sum" => 0}}
              }
            },
            %{"count" => 1, "states" => %{"warning" => 1}}
          ]
        },
        "jobs/B" => %{
          at: [hd(at)],
          values: [
            %{
              "count" => 1,
              "states" => %{"warning" => 1},
              "duration" => %{
                "count" => 1,
                "sum" => 1000,
                "states" => %{"warning" => %{"count" => 1, "sum" => 1000}}
              }
            }
          ]
        },
        "jobs-other/C" => %{
          at: [hd(at)],
          values: [%{"count" => 1, "duration" => %{"count" => 1, "sum" => 99999}}]
        }
      }
    }

    result = Activity.build(input, "jobs")
    line = Enum.find(result.series, &(&1[:y_axis] == "secondary"))
    assert line.chart_type == "line"
    assert line.stacked == false
    assert line.unit == "ms"
    assert [[_, average], [_, zero], [_, nil]] = line.data
    assert zero == 0
    assert_in_delta average, 2000 / 11, 0.0001
    assert result.total == 15
    assert Enum.map(line.average_samples, & &1.name) == ["jobs/A", "jobs/B"]

    warning = Activity.build(input, "jobs", "warning")

    assert Enum.find(warning.series, &(&1[:y_axis] == "secondary")).data ==
             Enum.zip(Enum.map(at, &DateTime.to_unix(&1, :millisecond)), [550.0, nil, nil])
             |> Enum.map(&Tuple.to_list/1)

    success = Activity.build(input, "jobs", "success")

    assert [[_, 100.0], [_, zero], [_, nil]] =
             Enum.find(success.series, &(&1[:y_axis] == "secondary")).data

    assert zero == 0

    refute Enum.any?(Activity.build(input, "jobs", "error").series, &(&1[:y_axis] == "secondary"))

    assert [[_, 1000.0], [_, nil], [_, nil]] =
             Enum.find(Activity.build(input, "jobs/B").series, &(&1[:y_axis] == "secondary")).data
  end

  test "legacy duration totals do not get reused for a state with no duration samples" do
    input = %{
      catalog: %{at: [1], values: [%{"keys" => %{"jobs/A" => 1}}]},
      metrics: %{
        "jobs/A" => %{
          at: [1],
          values: [
            %{
              "count" => 1,
              "states" => %{"warning" => 1},
              "duration" => %{"count" => 1, "sum" => 500}
            }
          ]
        }
      }
    }

    assert Enum.any?(Activity.build(input).series, &(&1[:y_axis] == "secondary"))
    refute Enum.any?(Activity.build(input, nil, "warning").series, &(&1[:y_axis] == "secondary"))
  end

  test "missing and unknown states stay unclassified rather than becoming success" do
    at = [~U[2026-09-01 00:00:00Z]]
    input = %{catalog: %{at: at, values: [%{"keys" => %{"old/Job" => 4}}]}}
    assert %{total: 4, series: [%{state: "unclassified"}]} = Activity.build(input)
    assert Activity.build(input, nil, "success").total == 0

    input =
      Map.put(input, :metrics, %{
        "old/Job" => %{at: at, values: [%{"states" => %{"cancelled" => 4}}]}
      })

    assert %{total: 4, series: [%{state: "unclassified"}]} = Activity.build(input)
  end
end
