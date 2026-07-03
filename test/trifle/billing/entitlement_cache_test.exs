defmodule Trifle.Billing.EntitlementCacheTest do
  # Flips the global cache TTL config, so must not run concurrently with
  # other tests reading entitlements.
  use Trifle.DataCase, async: false

  import Trifle.AccountsFixtures
  import Trifle.BillingFixtures

  alias Trifle.Billing
  alias Trifle.Billing.Entitlement

  setup do
    Application.put_env(:trifle, :billing_entitlement_cache_ttl_ms, 60_000)
    previous_mode = Application.get_env(:trifle, :deployment_mode)
    Application.put_env(:trifle, :deployment_mode, :saas)

    on_exit(fn ->
      Application.put_env(:trifle, :billing_entitlement_cache_ttl_ms, 0)
      Application.put_env(:trifle, :deployment_mode, previous_mode)
    end)

    user = user_fixture()

    {:ok, organization, _membership} =
      Trifle.Organizations.create_organization_with_owner(%{name: "Cache Org"}, user)

    # Ensure no stale entry from a previous test run of this org id.
    Trifle.Cache.invalidate({:org_entitlement, organization.id})

    %{organization: organization}
  end

  test "get_org_entitlement/1 serves repeated lookups from cache", %{organization: organization} do
    app_entitlement_fixture(organization, %{app_tier: "starter"})

    assert %Entitlement{app_tier: "starter"} = Billing.get_org_entitlement(organization.id)

    # Write behind the cache's back — a cached read must not see this yet.
    Repo.get_by!(Entitlement, organization_id: organization.id)
    |> Entitlement.changeset(%{app_tier: "pro"})
    |> Repo.update!()

    assert %Entitlement{app_tier: "starter"} = Billing.get_org_entitlement(organization.id)

    Trifle.Cache.invalidate({:org_entitlement, organization.id})

    assert %Entitlement{app_tier: "pro"} = Billing.get_org_entitlement(organization.id)
  end

  test "refresh_entitlements! invalidates the cached entitlement", %{organization: organization} do
    app_entitlement_fixture(organization, %{app_tier: "starter"})

    assert %Entitlement{app_tier: "starter"} = Billing.get_org_entitlement(organization.id)

    # Goes through upsert_entitlement, which must bust the cache.
    {:ok, _entitlement} = Billing.refresh_entitlements!(organization.id)

    refreshed = Billing.get_org_entitlement(organization.id)
    refute refreshed.app_tier == "starter"
  end
end
