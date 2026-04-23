defmodule Trifle.Billing.SourceAccessTest do
  use Trifle.DataCase, async: false

  import Trifle.BillingFixtures
  import Trifle.OrganizationsFixtures

  alias Trifle.Billing

  setup do
    previous =
      if Application.get_env(:trifle, :deployment_mode, :__missing__) == :__missing__ do
        :__missing__
      else
        Application.get_env(:trifle, :deployment_mode)
      end

    Application.put_env(:trifle, :deployment_mode, :saas)

    on_exit(fn ->
      case previous do
        :__missing__ -> Application.delete_env(:trifle, :deployment_mode)
        value -> Application.put_env(:trifle, :deployment_mode, value)
      end
    end)

    :ok
  end

  test "database access requires an active org entitlement in saas mode" do
    organization = organization_fixture()
    database = database_fixture(%{organization: organization})

    assert %{
             active?: false,
             billing_state: "locked",
             inactive_reason: :missing_app_subscription
           } = Billing.source_access_status(:database, database)

    app_entitlement_fixture(organization)

    assert %{active?: true, billing_state: "active", inactive_reason: nil} =
             Billing.source_access_status(:database, database)
  end

  test "project access stays pending until the project subscription is active" do
    organization = organization_fixture()
    project = project_fixture(%{organization: organization})
    app_entitlement_fixture(organization)

    assert %{
             active?: false,
             billing_state: "pending_checkout",
             inactive_reason: :pending_checkout
           } = Billing.source_access_status(:project, project)

    project_subscription_fixture(project)

    assert %{active?: true, billing_state: "active", inactive_reason: nil} =
             Billing.source_access_status(:project, project)
  end

  test "self-hosted mode bypasses billing enforcement for sources" do
    Application.put_env(:trifle, :deployment_mode, :self_hosted)

    organization = organization_fixture()
    database = database_fixture(%{organization: organization})
    project = project_fixture(%{organization: organization})

    assert %{active?: true, billing_state: "active", inactive_reason: nil} =
             Billing.source_access_status(:database, database)

    assert %{active?: true, billing_state: "active", inactive_reason: nil} =
             Billing.source_access_status(:project, project)
  end
end
