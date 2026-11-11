defmodule Trifle.Networking.HostGuard do
  @moduledoc """
  Stops tenant-supplied hosts from pointing the server at its own network (SSRF).

  Customers enter hosts for databases, SSH tunnels and S3-compatible trace
  storage, and the server connects to them. In a multi-tenant deployment those
  hosts must be on the public internet: loopback, private (RFC 1918), link-local
  and cloud-metadata addresses, carrier-grade NAT, and their IPv6 equivalents are
  refused. Private targets remain reachable the intended way, through a Tailscale
  network connection, which is routed by the gateway and not checked here.

  Enforcement is on in SaaS mode and off for self-hosted installs (whose databases
  normally live on a private network). Override with

      config :trifle, :allow_private_network_targets, true | false

  (`ALLOW_PRIVATE_NETWORK_TARGETS`).

  `check/1` resolves the name and rejects it if *any* address is internal.
  `check_literal/1` only looks at the text (IP literals and obviously local
  names) and does no DNS, so it is cheap enough for form validation.

  Limitation: the driver resolves the name again when it connects, so a DNS
  record that changes between the check and the connection (rebinding) is not
  caught. Connections keep using the host name because TLS verification needs it.
  """

  import Bitwise

  @type reason :: :forbidden_host | :unresolvable_host

  @local_names ~w(localhost localhost.localdomain ip6-localhost ip6-loopback)
  @local_suffixes ~w(.localhost .local .internal .cluster.local .svc)

  def enforced? do
    case Application.get_env(:trifle, :allow_private_network_targets) do
      true -> false
      false -> true
      _ -> Trifle.Config.saas_mode?()
    end
  end

  @doc "Full check: literal rules plus DNS resolution of every address."
  @spec check(term(), keyword()) :: :ok | {:error, reason()}
  def check(host, opts \\ []) do
    if Keyword.get(opts, :enforce, enforced?()) do
      with :ok <- literal(host) do
        resolve_and_check(normalize(host), Keyword.get(opts, :resolver, &resolve/1))
      end
    else
      :ok
    end
  end

  @doc "Text-only check (no DNS). Safe to call on every form change."
  @spec check_literal(term(), keyword()) :: :ok | {:error, reason()}
  def check_literal(host, opts \\ []) do
    if Keyword.get(opts, :enforce, enforced?()), do: literal(host), else: :ok
  end

  @doc "True for loopback, private, link-local, CGNAT, multicast and unspecified addresses."
  def internal_address?({a, b, _c, _d}) do
    a == 0 or a == 10 or a == 127 or
      (a == 100 and b >= 64 and b <= 127) or
      (a == 169 and b == 254) or
      (a == 172 and b >= 16 and b <= 31) or
      (a == 192 and b == 168) or
      (a == 192 and b == 0) or
      (a == 198 and b in [18, 19]) or
      a >= 224
  end

  def internal_address?({0, 0, 0, 0, 0, 0, 0, 0}), do: true
  def internal_address?({0, 0, 0, 0, 0, 0, 0, 1}), do: true

  # IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::/96): judge the embedded address.
  def internal_address?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: internal_address?(embedded(hi, lo))

  def internal_address?({0x64, 0xFF9B, 0, 0, 0, 0, hi, lo}),
    do: internal_address?(embedded(hi, lo))

  def internal_address?({first, _, _, _, _, _, _, _}) do
    # fc00::/7 unique local, fe80::/10 link-local, ff00::/8 multicast
    (first &&& 0xFE00) == 0xFC00 or (first &&& 0xFFC0) == 0xFE80 or (first &&& 0xFF00) == 0xFF00
  end

  def internal_address?(_), do: true

  defp embedded(hi, lo), do: {hi >>> 8, hi &&& 0xFF, lo >>> 8, lo &&& 0xFF}

  defp literal(host) do
    case normalize(host) do
      nil ->
        {:error, :forbidden_host}

      name ->
        case parse_ip(name) do
          {:ok, address} ->
            if internal_address?(address), do: {:error, :forbidden_host}, else: :ok

          :error ->
            # A colon outside an IPv6 literal means a port or other junk was included.
            if name in @local_names or Enum.any?(@local_suffixes, &String.ends_with?(name, &1)) or
                 not String.contains?(name, ".") or String.contains?(name, ":") do
              # Single-label names resolve through the search domain, i.e. to
              # neighbours on the server's own network.
              {:error, :forbidden_host}
            else
              :ok
            end
        end
    end
  end

  defp resolve_and_check(name, resolver) do
    case parse_ip(name) do
      {:ok, _address} ->
        :ok

      :error ->
        case resolver.(name) do
          [] ->
            {:error, :unresolvable_host}

          addresses ->
            if Enum.any?(addresses, &internal_address?/1),
              do: {:error, :forbidden_host},
              else: :ok
        end
    end
  end

  defp resolve(name) do
    charlist = String.to_charlist(name)

    Enum.flat_map([:inet, :inet6], fn family ->
      case :inet.getaddrs(charlist, family) do
        {:ok, addresses} -> addresses
        _ -> []
      end
    end)
  end

  # Accepts "[::1]", trailing dots and mixed case; rejects anything that is not a
  # plain host (userinfo, ports, paths, whitespace).
  defp normalize(host) when is_binary(host) do
    name =
      host
      |> String.trim()
      |> String.downcase()
      |> String.trim_leading("[")
      |> String.trim_trailing("]")
      |> String.trim_trailing(".")

    if name != "" and String.match?(name, ~r/\A[a-z0-9._:\-]+\z/), do: name
  end

  defp normalize(_), do: nil

  defp parse_ip(name) do
    case :inet.parse_strict_address(String.to_charlist(name)) do
      {:ok, address} ->
        {:ok, address}

      _ ->
        # Decimal/hex/short forms ("2130706433", "0x7f.1", "127.1") that libc
        # would still accept as IPv4.
        case :inet.parse_ipv4_address(String.to_charlist(name)) do
          {:ok, address} -> {:ok, address}
          _ -> :error
        end
    end
  end

  def message(:forbidden_host),
    do: "must be a public host. Use a Tailscale connection to reach private networks"

  def message(:unresolvable_host), do: "could not be resolved"
end
