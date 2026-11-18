defmodule Trifle.RateLimit.RedisBackendTest do
  # Toggles global rate-limit config and owns the named Redis connection.
  # Needs the Redis service from docker-compose (also started in CI).
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Trifle.RateLimit
  alias Trifle.RateLimit.RedisBackend

  @redis_url System.get_env("REDIS_URL") || "redis://redis:6379"

  setup do
    previous = Application.get_env(:trifle, RateLimit, [])
    on_exit(fn -> Application.put_env(:trifle, RateLimit, previous) end)

    {:ok, subject: "subject-#{System.unique_integer([:positive])}-#{System.os_time()}"}
  end

  defp configure(url) do
    Application.put_env(:trifle, RateLimit,
      enabled: true,
      backend: :redis,
      redis_url: url,
      policies: %{test_small: {3, 60_000}}
    )
  end

  defp redis_key(key, now_ms, window_ms) do
    digest = :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.encode16(case: :lower)
    "trifle:rate:#{digest}:#{div(now_ms, window_ms)}"
  end

  test "is not started and not consulted unless configured" do
    Application.put_env(:trifle, RateLimit, enabled: true)

    refute RedisBackend.configured?()
    assert RedisBackend.start_link() == :ignore
  end

  describe "with Redis" do
    setup do
      configure(@redis_url)
      start_supervised!(RedisBackend)
      :ok
    end

    test "allows up to the limit, then denies until the window ends", %{subject: subject} do
      for _ <- 1..3, do: assert(RateLimit.check(:test_small, subject) == :ok)

      assert {:error, {:rate_limited, retry_after_ms}} = RateLimit.check(:test_small, subject)
      assert retry_after_ms > 0 and retry_after_ms <= 60_000
      assert RateLimit.check(:test_small, subject <> "-other") == :ok
    end

    test "the count is shared: hits made by another node count here", %{subject: subject} do
      key = {:test_small, subject}
      now = System.system_time(:millisecond)

      # Another node has its own connection; the key is what they share.
      {:ok, other} = Redix.start_link(@redis_url)
      {:ok, 3} = Redix.command(other, ["INCRBY", redis_key(key, now, 60_000), "3"])

      assert {:deny, _} = RedisBackend.hit(key, 60_000, 3, now)
    end

    test "keys expire with their window and hold no readable subject", %{subject: subject} do
      key = {:test_small, "person@example.com-#{subject}"}
      now = System.system_time(:millisecond)

      assert {:allow, 1} = RedisBackend.hit(key, 60_000, 3, now)

      {:ok, conn} = Redix.start_link(@redis_url)
      {:ok, keys} = Redix.command(conn, ["KEYS", "trifle:rate:*"])
      refute Enum.any?(keys, &String.contains?(&1, "example.com"))

      {:ok, ttl} = Redix.command(conn, ["PTTL", redis_key(key, now, 60_000)])
      assert ttl > 0 and ttl <= 60_000
    end
  end

  test "falls back to counting on this node when Redis is unreachable", %{subject: subject} do
    # Nothing listens on this port.
    configure("redis://127.0.0.1:1")
    start_supervised!(RedisBackend)
    :persistent_term.erase({RateLimit, :redis_warned_at})

    log =
      capture_log(fn ->
        for _ <- 1..3, do: assert(RateLimit.check(:test_small, subject) == :ok)
        assert {:error, {:rate_limited, _}} = RateLimit.check(:test_small, subject)
      end)

    # Warned once, not once per request.
    assert length(String.split(log, "Redis backend unavailable")) == 2
  end
end
