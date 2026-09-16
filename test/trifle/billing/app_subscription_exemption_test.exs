defmodule Trifle.Billing.AppSubscriptionExemptionTest do
  use Trifle.DataCase, async: false

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Billing
  alias Trifle.Billing.{Entitlement, Subscription}
  alias Trifle.Organizations

  setup do
    on_exit(
      Trifle.ConfigFixtures.enable_saas_with_projects(billing_entitlement_cache_ttl_ms: 60_000)
    )

    organization = organization_fixture()
    on_exit(fn -> Trifle.Cache.invalidate({:org_entitlement, organization.id}) end)
    %{organization: organization}
  end

  test "exemption grants database access and survives repeated refreshes", %{organization: org} do
    database = database_fixture(%{organization: org})
    assert {:error, :missing_app_subscription} = Billing.app_access_allowed_for_org_id(org.id)

    for _ <- 1..2 do
      assert {:ok, %Entitlement{app_tier: "internal", seat_limit: nil, billing_locked: false}} =
               Billing.set_app_subscription_exempt(org.id, true)

      # The original struct still has false: refresh must read persisted state.
      assert {:ok, %Entitlement{app_tier: "internal", projects_enabled: true}} =
               Billing.refresh_entitlements!(org)

      assert :ok = Billing.app_access_allowed_for_org_id(org.id)
      refute Billing.billing_locked_for_org?(org.id)
      assert %{active?: true} = Billing.source_access_status(:database, database)
    end

    assert Organizations.get_organization!(org.id).app_subscription_exempt
    refute Repo.get_by(Subscription, organization_id: org.id)
  end

  test "disabling clears cached access and restores the missing subscription lock", %{
    organization: org
  } do
    assert {:ok, _} = Billing.set_app_subscription_exempt(org.id, true)
    assert :ok = Billing.app_access_allowed_for_org_id(org.id)

    assert {:ok, %Entitlement{billing_locked: true, lock_reason: "missing_app_subscription"}} =
             Billing.set_app_subscription_exempt(org.id, false)

    assert {:error, :missing_app_subscription} = Billing.app_access_allowed_for_org_id(org.id)
    refute Organizations.get_organization!(org.id).app_subscription_exempt
  end

  test "disabling derives the entitlement from the real paid subscription", %{organization: org} do
    plan = app_plan_fixture(%{tier_key: "team", seat_limit: 10})
    subscription = app_subscription_fixture(org, %{stripe_price_id: plan.stripe_price_id})

    assert {:ok, _} = Billing.set_app_subscription_exempt(org.id, true)

    assert {:ok, %Entitlement{app_tier: "team", seat_limit: 10, billing_locked: false}} =
             Billing.set_app_subscription_exempt(org.id, false)

    assert Repo.get!(Subscription, subscription.id) == subscription
  end

  test "Stripe cancellation preserves the exemption and becomes effective after disabling it", %{
    organization: org
  } do
    subscription = app_subscription_fixture(org, %{metadata: %{"app_tier" => "starter"}})
    assert {:ok, _} = Billing.set_app_subscription_exempt(org.id, true)

    assert :ok =
             Billing.process_stripe_event(%{
               "type" => "customer.subscription.deleted",
               "data" => %{
                 "object" => %{
                   "id" => subscription.stripe_subscription_id,
                   "customer" => "cus_internal",
                   "status" => "canceled",
                   "metadata" => %{
                     "organization_id" => org.id,
                     "scope_type" => "app",
                     "app_tier" => "starter"
                   },
                   "items" => %{"data" => []}
                 }
               }
             })

    assert Repo.get!(Subscription, subscription.id).status == "canceled"

    assert %Entitlement{app_tier: "internal", billing_locked: false} =
             Billing.get_org_entitlement(org.id)

    assert {:ok, %Entitlement{billing_locked: true}} =
             Billing.set_app_subscription_exempt(org.id, false)
  end

  test "hosted projects still require their own subscription", %{organization: org} do
    project = project_fixture(%{organization: org})
    assert {:ok, _} = Billing.set_app_subscription_exempt(org.id, true)

    assert %{active?: false, inactive_reason: :pending_checkout} =
             Billing.source_access_status(:project, project)

    project_subscription_fixture(project)
    assert %{active?: true} = Billing.source_access_status(:project, project)
  end

  test "ordinary organization writes cannot enable or remove the exemption", %{organization: org} do
    assert {:ok, created} =
             Organizations.create_organization(%{
               name: "Customer supplied flag",
               app_subscription_exempt: true
             })

    refute created.app_subscription_exempt

    assert {:ok, updated} =
             Organizations.update_organization(org, %{"app_subscription_exempt" => true})

    refute updated.app_subscription_exempt
    assert {:ok, _} = Billing.set_app_subscription_exempt(org.id, true)

    assert {:ok, updated} =
             org.id
             |> Organizations.get_organization!()
             |> Organizations.update_organization(%{"app_subscription_exempt" => false})

    assert updated.app_subscription_exempt
  end

  test "global admins and other organizations receive no automatic exemption", %{
    organization: org
  } do
    user = Trifle.AccountsFixtures.user_fixture()
    {:ok, user} = Trifle.Accounts.update_user_admin_status(user.id, true)
    other_org = organization_fixture(%{user: user, name: "Admin billing test organization"})

    assert {:ok, _} = Billing.set_app_subscription_exempt(org.id, true)
    assert {:ok, %Entitlement{billing_locked: true}} = Billing.refresh_entitlements!(other_org)

    assert {:error, :missing_app_subscription} =
             Billing.app_access_allowed_for_org_id(other_org.id)
  end

  test "reports invalid and missing organizations" do
    assert {:error, :invalid_organization_id} = Billing.set_app_subscription_exempt("bad", true)

    assert {:error, :organization_not_found} =
             Billing.set_app_subscription_exempt(Ecto.UUID.generate(), true)
  end

  test "self-hosted deployments store the flag without introducing billing", %{organization: org} do
    Application.put_env(:trifle, :deployment_mode, :self_hosted)
    assert {:ok, nil} = Billing.set_app_subscription_exempt(org.id, true)
    assert {:ok, nil} = Billing.set_app_subscription_exempt(org.id, false)
    assert :ok = Billing.app_access_allowed_for_org_id(org.id)
  end
end
