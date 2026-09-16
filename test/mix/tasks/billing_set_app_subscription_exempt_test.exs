defmodule Mix.Tasks.Billing.SetAppSubscriptionExemptTest do
  use Trifle.DataCase, async: false

  import ExUnit.CaptureIO
  import Trifle.OrganizationsFixtures

  alias Mix.Tasks.Billing.SetAppSubscriptionExempt, as: Task

  setup do
    on_exit(Trifle.ConfigFixtures.enable_saas_with_projects())
  end

  test "reports the selected organization and resulting entitlement when enabling and disabling" do
    org = organization_fixture()

    output = capture_io(fn -> Task.run([org.id, "true"]) end)
    assert output =~ "#{org.name} (#{org.id})"
    assert output =~ "app_subscription_exempt=true; app_tier=internal; billing_locked=false"

    output = capture_io(fn -> Task.run([org.id, "false"]) end)
    assert output =~ "app_subscription_exempt=false; app_tier=none; billing_locked=true"
  end

  test "rejects invalid arguments and unknown organizations" do
    for args <- [
          [],
          [Ecto.UUID.generate()],
          [Ecto.UUID.generate(), "yes"],
          ["id", "true", "extra"]
        ] do
      assert_raise Mix.Error, ~r/Usage:/, fn -> Task.run(args) end
    end

    assert_raise Mix.Error, "Organization ID must be a UUID", fn -> Task.run(["bad", "true"]) end
    assert_raise Mix.Error, ~r/was not found/, fn -> Task.run([Ecto.UUID.generate(), "true"]) end
  end
end
