defmodule Trifle.BillingFixtures do
  @moduledoc false

  import Ecto.Query

  alias Trifle.Billing.{Entitlement, Plan, Subscription}
  alias Trifle.Organizations.Organization
  alias Trifle.Organizations.Project
  alias Trifle.Repo

  def app_entitlement_fixture(%Organization{id: organization_id}, attrs \\ %{}) do
    entitlement =
      Repo.get_by(Entitlement, organization_id: organization_id) ||
        %Entitlement{organization_id: organization_id}

    defaults = %{
      organization_id: organization_id,
      app_tier: "starter",
      projects_enabled: true,
      billing_locked: false
    }

    entitlement
    |> Entitlement.changeset(Map.merge(defaults, attrs))
    |> Repo.insert_or_update!()
  end

  def project_subscription_fixture(%Project{} = project, attrs \\ %{}) do
    subscription =
      Repo.get_by(Subscription,
        organization_id: project.organization_id,
        scope_type: "project",
        scope_id: project.id
      ) ||
        %Subscription{
          organization_id: project.organization_id,
          scope_type: "project",
          scope_id: project.id
        }

    defaults = %{
      organization_id: project.organization_id,
      scope_type: "project",
      scope_id: project.id,
      stripe_subscription_id: "sub_#{System.unique_integer([:positive])}",
      status: "active"
    }

    subscription
    |> Subscription.changeset(Map.merge(defaults, attrs))
    |> Repo.insert_or_update!()
  end

  def app_plan_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    defaults = %{
      name: "Starter",
      scope_type: "app",
      tier_key: "starter",
      interval: "month",
      stripe_price_id: "price_app_#{unique}",
      currency: "usd",
      amount_cents: 3900,
      seat_limit: 3,
      active: true
    }

    %Plan{}
    |> Plan.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def project_plan_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    defaults = %{
      name: "100K",
      scope_type: "project",
      tier_key: "100k",
      interval: "month",
      stripe_price_id: "price_project_#{unique}",
      currency: "usd",
      amount_cents: 1900,
      hard_limit: 100_000,
      active: true
    }

    %Plan{}
    |> Plan.changeset(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  def app_subscription_fixture(%Organization{id: organization_id}, attrs \\ %{}) do
    subscription =
      Repo.one(
        from s in Subscription,
          where:
            s.organization_id == ^organization_id and s.scope_type == "app" and is_nil(s.scope_id)
      ) ||
        %Subscription{
          organization_id: organization_id,
          scope_type: "app",
          scope_id: nil
        }

    defaults = %{
      organization_id: organization_id,
      scope_type: "app",
      scope_id: nil,
      stripe_subscription_id: "sub_#{System.unique_integer([:positive])}",
      status: "active",
      interval: "month"
    }

    subscription
    |> Subscription.changeset(Map.merge(defaults, attrs))
    |> Repo.insert_or_update!()
  end
end
