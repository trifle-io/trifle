defmodule Trifle.Cache do
  @moduledoc """
  Application-wide cache built on Cachex.

  Single front door for short-TTL caching of expensive or repeated lookups
  (billing entitlements, cluster configs, ...). Keys are terms, typically
  `{:domain_tag, id}` tuples so a domain can invalidate its own entries.

  Invalidation is node-local; rely on short TTLs to bound staleness across
  nodes. Cache failures fall back to executing the loader directly, so a
  broken cache degrades to uncached behavior instead of errors.
  """

  @cache :trifle_cache

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {Cachex, :start_link, [@cache, []]},
      type: :supervisor
    }
  end

  @doc """
  Returns the cached value for `key`, or runs `loader` and caches its result
  for `ttl_ms`. `nil` results are cached too (a miss is worth remembering).
  """
  def fetch(key, ttl_ms, loader) when is_integer(ttl_ms) and is_function(loader, 0) do
    # Values are wrapped so a cached nil is distinguishable from a Cachex miss.
    case Cachex.fetch(@cache, key, fn _key -> {:commit, {:cached, loader.()}, expire: ttl_ms} end) do
      {:ok, {:cached, value}} -> value
      {:commit, {:cached, value}} -> value
      {:commit, {:cached, value}, _opts} -> value
      _other -> loader.()
    end
  end

  @doc """
  Reads a value written with `put/3`. Returns `{:ok, value}` or `:error` on a
  miss (or when the cache is unavailable).
  """
  def get(key) do
    case Cachex.get(@cache, key) do
      {:ok, {:cached, value}} -> {:ok, value}
      _other -> :error
    end
  end

  @doc """
  Stores `value` under `key` for `ttl_ms`. Failures are ignored.
  """
  def put(key, value, ttl_ms) when is_integer(ttl_ms) and ttl_ms > 0 do
    _ = Cachex.put(@cache, key, {:cached, value}, expire: ttl_ms)
    :ok
  end

  def invalidate(key) do
    Cachex.del(@cache, key)
    :ok
  end
end
