defmodule Trifle.Billing.StripeClient.MockTest do
  use ExUnit.Case, async: true

  alias Trifle.Billing.StripeClient.Mock

  test "create_portal_session/1 returns a deterministic response" do
    assert {:ok, response} = Mock.create_portal_session(%{})
    assert response["id"] == "mock_portal_session"
    assert response["url"] == "https://mock.stripe.portal/session"
  end

  test "create_checkout_session/1 returns a deterministic response" do
    assert {:ok, response} = Mock.create_checkout_session(%{})
    assert response["id"] == "mock_checkout_session"
    assert response["url"] == "https://mock.stripe.checkout/session"
  end

  test "create_customer/1 uses provided email when available" do
    assert {:ok, response} = Mock.create_customer(%{"email" => "billing@example.com"})
    assert response["id"] == "mock_cus_123"
    assert response["email"] == "billing@example.com"
  end

  test "update_subscription/2 keeps id and status stable" do
    assert {:ok, response} = Mock.update_subscription("sub_123", %{"price_id" => "price_new"})
    assert response["id"] == "sub_123"
    assert response["status"] == "active"
    assert response["price_id"] == "price_new"
  end

  test "get_subscription/1 returns active mock subscription" do
    assert {:ok, response} = Mock.get_subscription("sub_123")
    assert response["id"] == "sub_123"
    assert response["status"] == "active"
    assert response["price_id"] == "mock_price_monthly"
    assert is_integer(response["current_period_end"])
  end
end
