defmodule Trifle.Billing.StripeClient.Mock do
  def update_subscription(_subscription_id, _params) do
    {:error, :not_implemented}
  end

  def get_subscription(_subscription_id) do
    {:error, :not_implemented}
  end

  def create_portal_session(_params) do
    {:error, :not_implemented}
  end

  def create_customer(_params) do
    {:error, :not_implemented}
  end

  def create_checkout_session(_params) do
    {:error, :not_implemented}
  end
end
