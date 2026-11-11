defmodule Trifle.RateLimitTest do
  # Toggles global rate-limit config.
  use ExUnit.Case, async: false

  alias Trifle.RateLimit

  setup do
    previous = Application.get_env(:trifle, RateLimit, [])

    Application.put_env(:trifle, RateLimit,
      enabled: true,
      policies: %{test_small: {3, 60_000}, test_other: {1, 60_000}}
    )

    on_exit(fn -> Application.put_env(:trifle, RateLimit, previous) end)

    {:ok, subject: "subject-#{System.unique_integer([:positive])}"}
  end

  test "allows up to the limit, then denies with a retry time", %{subject: subject} do
    for _ <- 1..3, do: assert(RateLimit.check(:test_small, subject) == :ok)

    assert {:error, {:rate_limited, retry_after_ms}} = RateLimit.check(:test_small, subject)
    assert retry_after_ms > 0 and retry_after_ms <= 60_000
  end

  test "subjects and policies are counted separately", %{subject: subject} do
    for _ <- 1..3, do: RateLimit.check(:test_small, subject)

    assert RateLimit.check(:test_small, subject <> "-other") == :ok
    assert RateLimit.check(:test_other, subject) == :ok
    assert {:error, _} = RateLimit.check(:test_other, subject)
  end

  test "string subjects ignore case and surrounding space", %{subject: subject} do
    assert RateLimit.check(:test_other, "  #{String.upcase(subject)}@Example.com ") == :ok
    assert {:error, _} = RateLimit.check(:test_other, "#{subject}@example.com")
  end

  test "missing subjects are not limited" do
    for subject <- [nil, "", {:ip, nil}], _ <- 1..5 do
      assert RateLimit.check(:test_other, subject) == :ok
    end
  end

  test "check_all stops at the first denial", %{subject: subject} do
    assert RateLimit.check_all([{:test_other, subject}, {:test_small, subject}]) == :ok
    assert {:error, {:rate_limited, _}} = RateLimit.check_all([{:test_other, subject}])
  end

  test "disabled limiter lets everything through", %{subject: subject} do
    Application.put_env(:trifle, RateLimit, enabled: false, policies: %{test_other: {1, 60_000}})

    for _ <- 1..5, do: assert(RateLimit.check(:test_other, subject) == :ok)
  end

  test "unknown policies raise instead of silently allowing" do
    assert_raise ArgumentError, fn -> RateLimit.check(:no_such_policy, "x") end
  end

  test "retry_after_text is readable" do
    assert RateLimit.retry_after_text(400) == "1 second"
    assert RateLimit.retry_after_text(45_000) == "45 seconds"
    assert RateLimit.retry_after_text(180_000) == "3 minutes"
  end

  describe "client_ip/1" do
    test "uses the socket address by default, ignoring forwarded headers" do
      conn =
        Plug.Test.conn(:get, "/")
        |> Map.put(:remote_ip, {10, 0, 0, 7})
        |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.9")

      assert RateLimit.client_ip(conn) == "10.0.0.7"
    end

    test "reads the configured header, counting trusted proxies from the right" do
      Application.put_env(:trifle, RateLimit,
        enabled: true,
        client_ip_header: "x-forwarded-for",
        trusted_proxies: 1
      )

      conn =
        Plug.Test.conn(:get, "/")
        |> Map.put(:remote_ip, {10, 0, 0, 7})
        |> Plug.Conn.put_req_header("x-forwarded-for", "1.2.3.4, 203.0.113.9")

      # The left-most entry is client-supplied and must not be trusted.
      assert RateLimit.client_ip(conn) == "203.0.113.9"

      Application.put_env(:trifle, RateLimit,
        enabled: true,
        client_ip_header: "x-forwarded-for",
        trusted_proxies: 2
      )

      assert RateLimit.client_ip(conn) == "1.2.3.4"
    end

    test "falls back to the socket address when the header is missing or junk" do
      Application.put_env(:trifle, RateLimit, enabled: true, client_ip_header: "x-forwarded-for")

      conn = Plug.Test.conn(:get, "/") |> Map.put(:remote_ip, {10, 0, 0, 7})
      assert RateLimit.client_ip(conn) == "10.0.0.7"

      junk = Plug.Conn.put_req_header(conn, "x-forwarded-for", "not-an-ip")
      assert RateLimit.client_ip(junk) == "10.0.0.7"
    end
  end
end
