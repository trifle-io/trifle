defmodule Trifle.Billing.IngestAccessCacheTest do
  # Flips global config (cache TTL, deployment mode), so it cannot run concurrently.
  use Trifle.DataCase, async: false

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Billing
  alias Trifle.Billing.Subscription

  setup do
    previous_mode = Application.get_env(:trifle, :deployment_mode)
    Application.put_env(:trifle, :deployment_mode, :saas)
    Application.put_env(:trifle, :billing_ingest_access_cache_ttl_ms, 60_000)

    on_exit(fn ->
      Application.put_env(:trifle, :billing_ingest_access_cache_ttl_ms, 0)

      if is_nil(previous_mode),
        do: Application.delete_env(:trifle, :deployment_mode),
        else: Application.put_env(:trifle, :deployment_mode, previous_mode)
    end)

    organization = organization_fixture()
    project = project_fixture(%{organization: organization})
    app_entitlement_fixture(organization)
    Trifle.Cache.invalidate({:project_ingest_allowed, project.id})

    %{project: project}
  end

  test "a denial is never cached, so access opens as soon as the subscription is active", %{
    project: project
  } do
    assert {:error, :project_subscription_required} = Billing.ingest_allowed?(project)
    assert {:error, :project_subscription_required} = Billing.ingest_allowed?(project)

    project_subscription_fixture(project)

    assert :ok = Billing.ingest_allowed?(project)
  end

  test "a positive answer is reused until invalidated or expired", %{project: project} do
    project_subscription_fixture(project)
    assert :ok = Billing.ingest_allowed?(project)

    # Remove the subscription behind the cache's back.
    Repo.delete_all(from(s in Subscription, where: s.scope_id == ^project.id))

    assert :ok = Billing.ingest_allowed?(project)

    Trifle.Cache.invalidate({:project_ingest_allowed, project.id})

    assert {:error, :project_subscription_required} = Billing.ingest_allowed?(project)
  end

  test "with the TTL at zero every call re-checks", %{project: project} do
    Application.put_env(:trifle, :billing_ingest_access_cache_ttl_ms, 0)

    project_subscription_fixture(project)
    assert :ok = Billing.ingest_allowed?(project)

    Repo.delete_all(from(s in Subscription, where: s.scope_id == ^project.id))

    assert {:error, :project_subscription_required} = Billing.ingest_allowed?(project)
  end
end
