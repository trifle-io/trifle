defmodule Trifle.Networking.HostGuardTest do
  use ExUnit.Case, async: true

  alias Trifle.Networking.HostGuard

  defp literal(host), do: HostGuard.check_literal(host, enforce: true)

  describe "check_literal/2" do
    test "refuses loopback, private, link-local, metadata and other internal addresses" do
      for host <- [
            "127.0.0.1",
            "127.1",
            "2130706433",
            "0x7f.0.0.1",
            "0.0.0.0",
            "10.1.2.3",
            "172.16.0.1",
            "172.31.255.255",
            "192.168.1.10",
            "169.254.169.254",
            "100.64.0.1",
            "224.0.0.1",
            "::1",
            "[::1]",
            "::",
            "fe80::1",
            "fd00::1",
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.5",
            "64:ff9b::a00:1"
          ] do
        assert literal(host) == {:error, :forbidden_host}, "expected #{host} to be refused"
      end
    end

    test "refuses local names and single-label hosts" do
      for host <- [
            "localhost",
            "LOCALHOST.",
            "db.localhost",
            "postgres",
            "redis",
            "printer.local",
            "db.internal",
            "postgres.default.svc",
            "postgres.default.svc.cluster.local"
          ] do
        assert literal(host) == {:error, :forbidden_host}, "expected #{host} to be refused"
      end
    end

    test "refuses values that are not a plain host" do
      for host <- [nil, "", "  ", "user@127.0.0.1", "example.com/path", "example.com:5432", 42] do
        assert literal(host) == {:error, :forbidden_host}, "expected #{inspect(host)} refused"
      end
    end

    test "accepts public addresses and names" do
      for host <- [
            "8.8.8.8",
            "172.15.0.1",
            "172.32.0.1",
            "100.63.255.255",
            "2606:4700:4700::1111",
            "db.example.com",
            "DB.Example.COM."
          ] do
        assert literal(host) == :ok, "expected #{host} to be accepted"
      end
    end

    test "is a no-op when not enforced" do
      assert HostGuard.check_literal("127.0.0.1", enforce: false) == :ok
      assert HostGuard.check("127.0.0.1", enforce: false) == :ok
    end
  end

  describe "check/2" do
    defp check(host, addresses) do
      HostGuard.check(host, enforce: true, resolver: fn _name -> addresses end)
    end

    test "accepts a name whose addresses are all public" do
      assert check("db.example.com", [{93, 184, 216, 34}, {0x2606, 0x2800, 0, 0, 0, 0, 0, 1}]) ==
               :ok
    end

    test "refuses a public-looking name that resolves to an internal address" do
      assert check("evil.example.com", [{127, 0, 0, 1}]) == {:error, :forbidden_host}
      assert check("evil.example.com", [{169, 254, 169, 254}]) == {:error, :forbidden_host}
    end

    test "refuses when any one of several addresses is internal" do
      assert check("mixed.example.com", [{93, 184, 216, 34}, {10, 0, 0, 5}]) ==
               {:error, :forbidden_host}
    end

    test "reports names that do not resolve" do
      assert check("nope.example.com", []) == {:error, :unresolvable_host}
    end

    test "does not resolve IP literals" do
      resolver = fn _ -> flunk("should not resolve an IP literal") end

      assert HostGuard.check("8.8.8.8", enforce: true, resolver: resolver) == :ok

      assert HostGuard.check("10.0.0.1", enforce: true, resolver: resolver) ==
               {:error, :forbidden_host}
    end
  end
end
