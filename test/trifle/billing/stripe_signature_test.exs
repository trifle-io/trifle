defmodule Trifle.Billing.StripeSignatureTest do
  use ExUnit.Case, async: true

  alias Trifle.Billing.StripeSignature

  test "verifies signatures when header parts contain whitespace" do
    payload = ~s({"id":"evt_test_123"})
    secret = "whsec_test_secret"
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    signature =
      "#{timestamp}.#{payload}"
      |> then(&:crypto.mac(:hmac, :sha256, secret, &1))
      |> Base.encode16(case: :lower)

    header = "t=#{timestamp}, v1=#{signature}"

    assert :ok == StripeSignature.verify(payload, header, secret, 3600)
  end
end
