defmodule TrifleWeb.BodyReaderTest do
  use ExUnit.Case, async: true

  alias TrifleWeb.BodyReader

  test "stores raw body for canonical Stripe webhook path" do
    conn = Plug.Test.conn("POST", "/webhooks/stripe", ~s({"id":"evt_123"}))
    {:ok, _body, conn} = BodyReader.read_body(conn, [])

    assert conn.assigns[:raw_body] == ~s({"id":"evt_123"})
  end

  test "does not store raw body for removed Stripe webhook alias path" do
    conn = Plug.Test.conn("POST", "/stripe/webhook", ~s({"id":"evt_123"}))
    {:ok, _body, conn} = BodyReader.read_body(conn, [])

    refute Map.has_key?(conn.assigns, :raw_body)
  end
end
