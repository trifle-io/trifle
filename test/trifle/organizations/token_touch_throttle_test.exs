defmodule Trifle.Organizations.TokenTouchThrottleTest do
  use Trifle.DataCase

  import Trifle.AccountsFixtures

  alias Trifle.Organizations
  alias Trifle.Organizations.OrganizationApiToken
  alias Trifle.Organizations.TokenTouchThrottle

  defp unique_hash, do: "throttle-test-#{System.unique_integer([:positive])}"

  describe "allow?/2" do
    test "allows the first touch and throttles subsequent ones" do
      hash = unique_hash()

      assert TokenTouchThrottle.allow?(hash)
      refute TokenTouchThrottle.allow?(hash)
      refute TokenTouchThrottle.allow?(hash)
    end

    test "allows again after the interval passes" do
      hash = unique_hash()

      assert TokenTouchThrottle.allow?(hash, 25)
      refute TokenTouchThrottle.allow?(hash, 25)

      Process.sleep(50)

      assert TokenTouchThrottle.allow?(hash, 25)
    end

    test "throttles tokens independently" do
      hash_a = unique_hash()
      hash_b = unique_hash()

      assert TokenTouchThrottle.allow?(hash_a)
      assert TokenTouchThrottle.allow?(hash_b)
      refute TokenTouchThrottle.allow?(hash_a)
      refute TokenTouchThrottle.allow?(hash_b)
    end
  end

  describe "touch_organization_api_token/2 throttling" do
    setup do
      user = user_fixture()

      {:ok, organization, _membership} =
        Organizations.create_organization_with_owner(%{name: "Throttle Org"}, user)

      {:ok, _record, token} =
        Organizations.create_organization_api_token(user, %{
          name: "Throttle token",
          organization_id: organization.id
        })

      %{token: token}
    end

    test "writes on first touch, skips writes within the throttle window", %{token: token} do
      assert :ok =
               Organizations.touch_organization_api_token(token, %{last_used_from: "first-host"})

      token_hash = OrganizationApiToken.hash_token(token)
      record = Repo.get_by!(OrganizationApiToken, token_hash: token_hash)
      assert record.last_used_from == "first-host"
      assert record.last_used_at

      assert :ok =
               Organizations.touch_organization_api_token(token, %{last_used_from: "second-host"})

      record = Repo.get_by!(OrganizationApiToken, token_hash: token_hash)
      assert record.last_used_from == "first-host"
    end
  end
end
