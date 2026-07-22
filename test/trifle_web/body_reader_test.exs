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

  test "decompresses gzip request bodies" do
    body = ~s({"key":"orders","values":{"count":1}})

    conn =
      Plug.Test.conn("POST", "/api/v1/metrics", :zlib.gzip(body))
      |> Plug.Conn.put_req_header("content-encoding", "gzip")

    assert {:ok, ^body, _conn} = BodyReader.read_body(conn, length: 1_000)
  end

  test "rejects malformed gzip request bodies" do
    conn =
      Plug.Test.conn("POST", "/api/v1/metrics", "not-gzip")
      |> Plug.Conn.put_req_header("content-encoding", "gzip")

    assert {:error, :invalid_gzip} = BodyReader.read_body(conn, length: 1_000)
  end

  test "rejects gzip bodies larger than the decompressed limit" do
    conn =
      Plug.Test.conn("POST", "/api/v1/metrics", :zlib.gzip(String.duplicate("a", 101)))
      |> Plug.Conn.put_req_header("content-encoding", "gzip")

    assert {:more, "", _conn} = BodyReader.read_body(conn, length: 100)
  end
end
