defmodule Trifle.RateLimit.RedisBackend do
  @moduledoc """
  Shared rate-limit counters in Redis, so a limit holds across all app nodes.

  Enabled with

      config :trifle, Trifle.RateLimit, backend: :redis, redis_url: "redis://..."

  (`RATE_LIMIT_BACKEND=redis`, `RATE_LIMIT_REDIS_URL`). Counting is a fixed
  window, the same as the in-memory backend: one key per policy, subject and
  window, incremented atomically and expired with the window.

  Subjects (IP addresses, email addresses) are hashed before they are used in a
  key, so Redis holds no personal data.

  If Redis is unreachable or slow, `hit/3` returns `{:error, reason}` and
  `Trifle.RateLimit` counts on the local node instead; a Redis outage weakens the
  limits to per-node, it never blocks or fails requests.
  """

  @name __MODULE__
  # A limiter check sits in front of logins and API calls; it must not hold them up.
  @timeout_ms 250

  # KEYS[1] = counter key, ARGV[1] = window in ms. Returns the new count.
  @script """
  local count = redis.call('INCR', KEYS[1])
  if count == 1 then
    redis.call('PEXPIRE', KEYS[1], ARGV[1])
  end
  return count
  """

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :worker}
  end

  @doc "Starts the connection, or returns `:ignore` when the Redis backend is not configured."
  def start_link(_opts \\ []) do
    case url() do
      url when is_binary(url) ->
        # sync_connect: false, so an unreachable Redis cannot stop the app from booting.
        Redix.start_link(url, name: @name, sync_connect: false, timeout: 2_000)

      _ ->
        :ignore
    end
  end

  @doc "Whether the Redis backend is configured."
  def configured?, do: is_binary(url())

  @doc """
  Counts one hit. Returns `{:allow, count}`, `{:deny, retry_after_ms}` or
  `{:error, reason}` when Redis could not be asked.
  """
  def hit(key, window_ms, limit, now_ms \\ System.system_time(:millisecond)) do
    window = div(now_ms, window_ms)
    redis_key = "trifle:rate:" <> digest(key) <> ":" <> Integer.to_string(window)
    command = ["EVAL", @script, "1", redis_key, Integer.to_string(window_ms)]

    case Redix.command(@name, command, timeout: @timeout_ms) do
      {:ok, count} when is_integer(count) and count <= limit ->
        {:allow, count}

      {:ok, count} when is_integer(count) ->
        {:deny, window_ms - rem(now_ms, window_ms)}

      {:ok, other} ->
        {:error, {:unexpected_reply, other}}

      {:error, reason} ->
        {:error, reason}
    end
  catch
    # The connection process is not running, or the call timed out.
    :exit, reason -> {:error, reason}
  end

  defp digest(key) do
    :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.encode16(case: :lower)
  end

  defp url do
    config = Application.get_env(:trifle, Trifle.RateLimit, [])

    with :redis <- Keyword.get(config, :backend, :ets),
         url when is_binary(url) and url != "" <- Keyword.get(config, :redis_url) do
      url
    else
      _ -> nil
    end
  end
end
