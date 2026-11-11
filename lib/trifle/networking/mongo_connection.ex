defmodule Trifle.Networking.MongoConnection do
  @moduledoc """
  Builds the driver options for a tenant MongoDB source.

  Every place that opens such a connection (the pool, setup, status checks) goes
  through here, so the same two protections always apply:

    * **No connection URL is built.** Host, port, database, user name, password
      and auth source are handed to the driver as separate options, exactly as
      entered. Nothing is parsed out of a string, so a credential containing `@`,
      `/`, `#` or `,` cannot become another address, and a database name such as
      `analytics+events` reaches the server unchanged. The host must still look
      like a single host.

    * **Only the checked host is contacted.** A MongoDB server announces the other
      members of its deployment and the driver connects to them. Where tenant
      hosts are restricted (`Trifle.Networking.HostGuard`), tenant connections use
      a single-server topology, so a public seed cannot steer the app towards
      internal addresses. This covers direct and SSH-tunnelled connections;
      Tailscale connections are already single-server. Platform-managed databases
      keep normal discovery.

  Consequence of the second point: point the source at a mongos or the primary;
  replica-set failover is not followed.
  """

  alias Trifle.Networking.{DatabaseTLS, HostGuard}

  @default_port 27017
  @default_database "admin"

  @doc """
  Options for `Mongo.start_link/1` for `database` reached through `endpoint`
  (from `Trifle.Networking.DatabaseEndpoint.resolve/1`), merged over `extra`.
  """
  @spec options(map(), map(), keyword()) :: {:ok, keyword()} | {:error, :invalid_host}
  def options(database, endpoint, extra \\ []) do
    host = to_string(endpoint.host || "")

    if valid_host?(host) do
      options =
        extra
        |> Keyword.drop([:url, :seeds])
        |> Keyword.merge(
          hostname: host,
          port: endpoint.port || database.port || @default_port,
          database: present(database.database_name) || @default_database
        )
        |> put_credentials(database)
        |> put_present(:auth_source, database.auth_database)
        |> DatabaseTLS.mongo(database)
        |> restrict_topology(database)

      {:ok, options}
    else
      {:error, :invalid_host}
    end
  end

  # One host: no separators that could add a second address.
  defp valid_host?(host), do: String.match?(host, ~r/\A[A-Za-z0-9._:\-]+\z/)

  # Credentials are only sent as a pair, as before.
  defp put_credentials(options, database) do
    if present(database.username) && present(database.password) do
      options
      |> Keyword.put(:username, database.username)
      |> Keyword.put(:password, database.password)
    else
      options
    end
  end

  defp put_present(options, key, value) do
    case present(value) do
      nil -> options
      value -> Keyword.put(options, key, value)
    end
  end

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

  defp restrict_topology(options, %{managed_key: key}) when is_binary(key), do: options

  defp restrict_topology(options, _database) do
    if HostGuard.enforced?(), do: Keyword.put(options, :type, :single), else: options
  end
end
