defmodule Trifle.Billing.StripeClient.Mock do
  def update_subscription(subscription_id, params),
    do: update_subscription(subscription_id, params, [])

  def update_subscription(subscription_id, params, _opts) do
    price_id =
      params[:price_id] ||
        params["price_id"] ||
        get_in(params, ["items", Access.at(0), "price"]) ||
        get_in(params, [:items, Access.at(0), :price]) ||
        get_in(params, [:items, Access.at(0), "price"]) ||
        "mock_price_monthly"

    {:ok,
     %{
       "id" => subscription_id,
       "status" => "active",
       "price_id" => price_id,
       id: subscription_id,
       status: "active",
       price_id: price_id
     }}
  end

  def get_subscription(subscription_id) do
    current_period_end = :os.system_time(:seconds) + 30 * 24 * 3600

    {:ok,
     %{
       "id" => subscription_id,
       "status" => "active",
       "price_id" => "mock_price_monthly",
       "current_period_end" => current_period_end,
       id: subscription_id,
       status: "active",
       price_id: "mock_price_monthly",
       current_period_end: current_period_end
     }}
  end

  def create_portal_session(params), do: create_portal_session(params, [])

  def create_portal_session(_params, _opts) do
    {:ok,
     %{
       "url" => "https://mock.stripe.portal/session",
       "id" => "mock_portal_session",
       url: "https://mock.stripe.portal/session",
       id: "mock_portal_session"
     }}
  end

  def create_customer(params), do: create_customer(params, [])

  def create_customer(params, _opts) do
    email = params[:email] || params["email"] || "mock@example.com"

    {:ok,
     %{
       "id" => "mock_cus_123",
       "email" => email,
       id: "mock_cus_123",
       email: email
     }}
  end

  def create_checkout_session(params), do: create_checkout_session(params, [])

  def create_checkout_session(_params, _opts) do
    {:ok,
     %{
       "url" => "https://mock.stripe.checkout/session",
       "id" => "mock_checkout_session",
       url: "https://mock.stripe.checkout/session",
       id: "mock_checkout_session"
     }}
  end
end
