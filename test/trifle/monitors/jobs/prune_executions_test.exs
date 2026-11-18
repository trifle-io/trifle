defmodule Trifle.Monitors.Jobs.PruneExecutionsTest do
  use Trifle.DataCase, async: false

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.AccountsFixtures
  alias Trifle.Monitors
  alias Trifle.Monitors.Execution
  alias Trifle.Monitors.Jobs.DispatchRunner
  alias Trifle.Monitors.Jobs.PruneExecutions
  alias Trifle.Organizations

  @now ~U[2026-11-18 12:00:00.000000Z]

  setup do
    on_exit(fn -> Application.delete_env(:trifle, :monitor_execution_retention_days) end)

    user = AccountsFixtures.user_fixture()
    organization = organization_fixture(%{user: user})
    app_entitlement_fixture(organization)
    membership = Organizations.get_membership_for_user(user)
    database = database_fixture(%{organization: organization})

    monitor = fn name ->
      {:ok, monitor} =
        Monitors.create_monitor_for_membership(user, membership, %{
          "name" => name,
          "type" => "alert",
          "alert_metric_key" => "latency",
          "alert_metric_path" => "$.global",
          "alert_timeframe" => "15m",
          "alert_granularity" => "5m",
          "source_type" => "database",
          "source_id" => database.id
        })

      monitor
    end

    %{monitor: monitor.("First"), other: monitor.("Second")}
  end

  defp execution(monitor, days_ago, status, kind) do
    Repo.insert!(%Execution{
      monitor_id: monitor.id,
      status: status,
      triggered_at: DateTime.add(@now, -days_ago * 86_400, :second),
      details: %{"kind" => kind}
    })
  end

  defp remaining(monitor) do
    from(e in Execution,
      where: e.monitor_id == ^monitor.id,
      order_by: [desc: e.triggered_at],
      select: {e.status, fragment("?->>'kind'", e.details), e.triggered_at}
    )
    |> Repo.all()
    |> Enum.map(fn {status, kind, at} -> {status, kind, div(DateTime.diff(@now, at), 86_400)} end)
  end

  defp cutoff(days), do: DateTime.add(@now, -days * 86_400, :second)

  test "deletes history older than the cutoff and keeps newer rows", %{monitor: monitor} do
    for days <- [1, 10, 29, 31, 45, 90], do: execution(monitor, days, "ok", "alert")

    assert PruneExecutions.prune(cutoff(30)) == 3

    assert remaining(monitor) == [{"ok", "alert", 1}, {"ok", "alert", 10}, {"ok", "alert", 29}]
  end

  test "keeps the latest run and the latest successful run however old they are", %{
    monitor: monitor
  } do
    # A quarterly report: everything is older than the cutoff.
    execution(monitor, 200, "ok", "report")
    execution(monitor, 110, "ok", "report")
    execution(monitor, 100, "error", "report")
    execution(monitor, 95, "error", "report")

    before_any = DispatchRunner.last_execution_map([monitor.id], "report")
    before_ok = DispatchRunner.last_execution_map([monitor.id], "report", ["ok"])

    assert PruneExecutions.prune(cutoff(30)) == 2

    assert remaining(monitor) == [{"error", "report", 95}, {"ok", "report", 110}]

    # What the dispatcher schedules from is unchanged.
    assert DispatchRunner.last_execution_map([monitor.id], "report") == before_any
    assert DispatchRunner.last_execution_map([monitor.id], "report", ["ok"]) == before_ok
  end

  test "monitors and kinds are judged separately", %{monitor: monitor, other: other} do
    execution(monitor, 60, "ok", "alert")
    execution(monitor, 50, "ok", "report")
    execution(other, 40, "ok", "alert")
    # Newer rows of another monitor or kind do not make these redundant.
    execution(other, 1, "ok", "report")

    assert PruneExecutions.prune(cutoff(30)) == 0
    assert length(remaining(monitor)) == 2
    assert length(remaining(other)) == 2
  end

  test "works through a backlog in batches", %{monitor: monitor} do
    for days <- 40..60, do: execution(monitor, days, "ok", "alert")
    execution(monitor, 1, "ok", "alert")

    assert PruneExecutions.prune(cutoff(30), 5) == 21
    assert remaining(monitor) == [{"ok", "alert", 1}]
  end

  test "the job uses the configured retention and 0 disables it", %{monitor: monitor} do
    old = DateTime.add(DateTime.utc_now(), -40 * 86_400, :second)

    Repo.insert!(%Execution{
      monitor_id: monitor.id,
      status: "ok",
      triggered_at: old,
      details: %{"kind" => "alert"}
    })

    Repo.insert!(%Execution{
      monitor_id: monitor.id,
      status: "ok",
      triggered_at: DateTime.utc_now(),
      details: %{"kind" => "alert"}
    })

    Application.put_env(:trifle, :monitor_execution_retention_days, 0)
    assert :ok = PruneExecutions.perform(%Oban.Job{})
    assert length(remaining(monitor)) == 2

    Application.put_env(:trifle, :monitor_execution_retention_days, 30)
    assert :ok = PruneExecutions.perform(%Oban.Job{})
    assert length(remaining(monitor)) == 1
  end
end
