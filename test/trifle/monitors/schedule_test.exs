defmodule Trifle.Monitors.ScheduleTest do
  use ExUnit.Case, async: true

  alias Trifle.Monitors.Monitor
  alias Trifle.Monitors.Schedule

  describe "granularity_minutes/1" do
    test "parses minute, hour, day and week units" do
      assert {:ok, 1} = Schedule.granularity_minutes("1m")
      assert {:ok, 15} = Schedule.granularity_minutes("15m")
      assert {:ok, 60} = Schedule.granularity_minutes("1h")
      assert {:ok, 180} = Schedule.granularity_minutes("3h")
      assert {:ok, 1440} = Schedule.granularity_minutes("1d")
      assert {:ok, 10_080} = Schedule.granularity_minutes("1w")
    end

    test "rounds second-based granularities up to whole minutes" do
      assert {:ok, 1} = Schedule.granularity_minutes("30s")
      assert {:ok, 2} = Schedule.granularity_minutes("61s")
    end

    test "falls back to one minute when missing" do
      assert {:ok, 1} = Schedule.granularity_minutes(nil)
      assert {:ok, 1} = Schedule.granularity_minutes("")
    end

    test "returns error for unsupported units" do
      assert :error = Schedule.granularity_minutes("5q")
      assert :error = Schedule.granularity_minutes("abc")
      assert :error = Schedule.granularity_minutes(15)
    end
  end

  describe "due?/3 for reports" do
    test "triggers each hour for hourly frequency" do
      monitor = %Monitor{
        id: "monitor-hourly",
        status: :active,
        type: :report,
        report_settings: %{frequency: :hourly}
      }

      hour = utc_dt({2024, 4, 10, 12, 0})
      assert Schedule.due?(monitor, hour, nil)
      refute Schedule.due?(monitor, utc_dt({2024, 4, 10, 12, 30}), hour)
      assert Schedule.due?(monitor, utc_dt({2024, 4, 10, 13, 0}), hour)
    end

    test "triggers once per day for daily frequency" do
      monitor = %Monitor{
        id: "monitor-1",
        status: :active,
        type: :report,
        report_settings: %{frequency: :daily}
      }

      midnight = utc_dt({2024, 4, 10, 0, 0})
      assert Schedule.due?(monitor, midnight, nil)
      refute Schedule.due?(monitor, utc_dt({2024, 4, 10, 1, 0}), midnight)
      assert Schedule.due?(monitor, utc_dt({2024, 4, 11, 0, 0}), midnight)
    end

    test "runs weekly monitors on Mondays at midnight" do
      monitor = %Monitor{
        id: "monitor-2",
        status: :active,
        type: :report,
        report_settings: %{frequency: :weekly}
      }

      # Monday
      monday = utc_dt({2024, 4, 8, 0, 0})
      assert Schedule.due?(monitor, monday, nil)
      refute Schedule.due?(monitor, utc_dt({2024, 4, 9, 0, 0}), monday)
      assert Schedule.due?(monitor, utc_dt({2024, 4, 15, 0, 0}), monday)
    end

    test "runs monthly monitors on first day midnight" do
      monitor = %Monitor{
        id: "monitor-3",
        status: :active,
        type: :report,
        report_settings: %{frequency: :monthly}
      }

      first = utc_dt({2024, 5, 1, 0, 0})
      assert Schedule.due?(monitor, first, nil)
      refute Schedule.due?(monitor, utc_dt({2024, 5, 1, 0, 5}), first)
      assert Schedule.due?(monitor, utc_dt({2024, 6, 1, 0, 0}), first)
    end
  end

  describe "due?/3 for alerts" do
    test "evaluates one-minute granularity each minute" do
      monitor = %Monitor{
        id: "monitor-alert-1",
        status: :active,
        type: :alert,
        alert_granularity: "1m"
      }

      minute = utc_dt({2024, 4, 10, 12, 0})
      assert Schedule.due?(monitor, minute, nil)
      refute Schedule.due?(monitor, minute, minute)
      assert Schedule.due?(monitor, utc_dt({2024, 4, 10, 12, 1}), minute)
    end

    test "evaluates 15 minute granularity at bucket boundaries" do
      monitor = %Monitor{
        id: "monitor-alert-2",
        status: :active,
        type: :alert,
        alert_granularity: "15m"
      }

      boundary = utc_dt({2024, 4, 10, 12, 15})
      assert Schedule.due?(monitor, boundary, nil)
      refute Schedule.due?(monitor, utc_dt({2024, 4, 10, 12, 16}), boundary)
      assert Schedule.due?(monitor, utc_dt({2024, 4, 10, 12, 30}), boundary)
    end
  end

  defp utc_dt({year, month, day, hour, min}) do
    {:ok, naive} = NaiveDateTime.new(year, month, day, hour, min, 0)
    DateTime.from_naive!(naive, "Etc/UTC")
  end
end
