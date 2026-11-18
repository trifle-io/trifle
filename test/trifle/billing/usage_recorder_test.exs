defmodule Trifle.Billing.UsageRecorderTest do
  # Flips the deployment mode and uses the shared counter table.
  use Trifle.DataCase, async: false

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Billing
  alias Trifle.Billing.ProjectUsage
  alias Trifle.Billing.UsageRecorder

  setup do
    previous_mode = Application.get_env(:trifle, :deployment_mode)
    Application.put_env(:trifle, :deployment_mode, :saas)

    on_exit(fn ->
      if is_nil(previous_mode),
        do: Application.delete_env(:trifle, :deployment_mode),
        else: Application.put_env(:trifle, :deployment_mode, previous_mode)
    end)

    # Drop anything other tests left in the counters.
    :ets.delete_all_objects(UsageRecorder)

    organization = organization_fixture()
    project = project_fixture(%{organization: organization})
    app_entitlement_fixture(organization)

    %{project: project}
  end

  defp events_count(project) do
    Repo.one(from(u in ProjectUsage, where: u.project_id == ^project.id, select: u.events_count))
  end

  test "counts are held in memory and written as one total per project", %{project: project} do
    project_subscription_fixture(project)

    for _ <- 1..7, do: UsageRecorder.record(project)
    assert events_count(project) == nil

    assert UsageRecorder.flush() == 1
    assert events_count(project) == 7

    UsageRecorder.record(project, 3)
    assert UsageRecorder.flush() == 1
    assert events_count(project) == 10

    assert UsageRecorder.flush() == 0
  end

  test "ingest is refused once the plan's hard limit is reached", %{project: project} do
    project_subscription_fixture(project, %{metadata: %{"project_hard_limit" => 5}})

    UsageRecorder.record(project, 4)
    UsageRecorder.flush()
    assert :ok = Billing.ingest_allowed?(project)

    UsageRecorder.record(project, 1)
    UsageRecorder.flush()
    assert {:error, :project_usage_limit_reached} = Billing.ingest_allowed?(project)
  end

  test "reaching the limit drops the cached positive answer", %{project: project} do
    Application.put_env(:trifle, :billing_ingest_access_cache_ttl_ms, 60_000)
    on_exit(fn -> Application.put_env(:trifle, :billing_ingest_access_cache_ttl_ms, 0) end)
    Trifle.Cache.invalidate({:project_ingest_allowed, project.id})

    project_subscription_fixture(project, %{metadata: %{"project_hard_limit" => 2}})
    assert :ok = Billing.ingest_allowed?(project)

    UsageRecorder.record(project, 2)
    UsageRecorder.flush()

    assert {:error, :project_usage_limit_reached} = Billing.ingest_allowed?(project)
  end

  test "a plan without a hard limit is counted but never refused", %{project: project} do
    project_subscription_fixture(project)

    UsageRecorder.record(project, 1_000_000)
    UsageRecorder.flush()

    assert events_count(project) == 1_000_000
    assert :ok = Billing.ingest_allowed?(project)
  end

  test "a project without a subscription is not counted and does not block the flush", %{
    project: project
  } do
    UsageRecorder.record(project, 3)

    assert UsageRecorder.flush() == 1
    assert events_count(project) == nil
  end

  describe "billing periods" do
    @old_start ~U[2026-10-01 00:00:00Z]
    @renewal ~U[2026-11-01 00:00:00Z]
    @new_end ~U[2026-12-01 00:00:00Z]

    defp usage_by_period(project) do
      from(u in ProjectUsage,
        where: u.project_id == ^project.id,
        select: {u.period_start, u.events_count}
      )
      |> Repo.all()
      |> Map.new()
    end

    test "events received before a renewal count against the period they arrived in", %{
      project: project
    } do
      project_subscription_fixture(project, %{
        current_period_start: @old_start,
        current_period_end: @renewal
      })

      before_renewal = DateTime.to_unix(@renewal) - 5
      UsageRecorder.record(project, 2, before_renewal - 60)
      UsageRecorder.flush()

      # Still in memory when the subscription renews.
      UsageRecorder.record(project, 7, before_renewal)

      project_subscription_fixture(project, %{
        current_period_start: @renewal,
        current_period_end: @new_end
      })

      UsageRecorder.record(project, 3, DateTime.to_unix(@renewal) + 5)
      UsageRecorder.flush()

      assert usage_by_period(project) == %{@old_start => 9, @renewal => 3}
    end

    test "late events for an old period never lock the project in the new one", %{
      project: project
    } do
      project_subscription_fixture(project, %{
        current_period_start: @old_start,
        current_period_end: @renewal,
        metadata: %{"project_hard_limit" => 5}
      })

      UsageRecorder.record(project, 1, DateTime.to_unix(@renewal) - 30)
      UsageRecorder.flush()
      UsageRecorder.record(project, 50, DateTime.to_unix(@renewal) - 5)

      project_subscription_fixture(project, %{
        current_period_start: @renewal,
        current_period_end: @new_end,
        metadata: %{"project_hard_limit" => 5}
      })

      UsageRecorder.flush()

      assert usage_by_period(project) == %{@old_start => 51}
      assert :ok = Billing.ingest_allowed?(project)
    end
  end

  describe "failures" do
    import ExUnit.CaptureLog

    test "reaching the limit stores the count, the lock and the project state together", %{
      project: project
    } do
      project_subscription_fixture(project, %{metadata: %{"project_hard_limit" => 3}})

      UsageRecorder.record(project, 3)
      UsageRecorder.flush()

      usage = Repo.get_by!(ProjectUsage, project_id: project.id)
      assert usage.events_count == 3
      assert usage.locked_at
      assert Repo.reload!(project).billing_state == "locked"
    end

    test "a write that fails part-way stores nothing and is retried once, not twice", %{
      project: project
    } do
      project_subscription_fixture(project, %{metadata: %{"project_hard_limit" => 3}})
      UsageRecorder.record(project, 2)
      UsageRecorder.flush()
      assert events_count(project) == 2

      # Make the last step of the next write (locking the project) fail after the
      # increment has been issued inside the transaction.
      Repo.query!("""
      CREATE OR REPLACE FUNCTION pg_temp.fail_project_lock() RETURNS trigger AS $$
      BEGIN
        IF NEW.billing_state = 'locked' THEN RAISE EXCEPTION 'simulated failure'; END IF;
        RETURN NEW;
      END $$ LANGUAGE plpgsql
      """)

      Repo.query!("""
      CREATE TRIGGER fail_project_lock BEFORE UPDATE ON projects
      FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_project_lock()
      """)

      UsageRecorder.record(project, 4)

      log = capture_log(fn -> assert UsageRecorder.flush() == 0 end)
      assert log =~ "will retry 4 events"

      # Rolled back as a whole: the increment is not there, nor the lock.
      assert events_count(project) == 2
      refute Repo.get_by!(ProjectUsage, project_id: project.id).locked_at

      # A second failing flush does not pile the batch up either.
      capture_log(fn -> assert UsageRecorder.flush() == 0 end)
      assert events_count(project) == 2

      Repo.query!("DROP TRIGGER fail_project_lock ON projects")

      assert UsageRecorder.flush() == 1
      assert events_count(project) == 6
      assert Repo.reload!(project).billing_state == "locked"
    end

    test "a count that has failed for over an hour is dropped", %{project: project} do
      project_subscription_fixture(project)

      Repo.query!("""
      CREATE OR REPLACE FUNCTION pg_temp.fail_usage() RETURNS trigger AS $$
      BEGIN RAISE EXCEPTION 'simulated failure'; END $$ LANGUAGE plpgsql
      """)

      Repo.query!("""
      CREATE TRIGGER fail_usage BEFORE INSERT ON project_billing_usage
      FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_usage()
      """)

      UsageRecorder.record(project, 5, System.os_time(:second) - 4_000)

      log = capture_log(fn -> assert UsageRecorder.flush() == 1 end)
      assert log =~ "dropped 5 events"
      assert :ets.tab2list(UsageRecorder) == []
    end
  end

  test "nothing is counted when billing is disabled", %{project: project} do
    Application.put_env(:trifle, :deployment_mode, :self_hosted)

    UsageRecorder.record(project, 3)

    assert :ets.tab2list(UsageRecorder) == []
  end
end
