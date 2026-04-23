defmodule Trifle.BillingFixtures do
  @moduledoc false

  alias Trifle.Billing.{Entitlement, Subscription}
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
end
