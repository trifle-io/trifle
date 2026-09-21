defmodule Trifle.Networking.Tailscale do
  @moduledoc "Resolves configured resources to organization-scoped tailnet streams."
  alias Trifle.Organizations.NetworkConnections
  alias Trifle.Networking.Forwarder

  def database_endpoint(database) do
    with {:ok, route} <- route(database, :database),
         {:ok, port} <- Forwarder.endpoint(route, :tcp) do
      {:ok,
       %{
         host: "127.0.0.1",
         port: port,
         via: :tailscale,
         source_host: database.host,
         source_port: database.port
       }}
    end
  end

  def s3_options(database) do
    with {:ok, route} <- route(database, :s3),
         {:ok, port} <- Forwarder.endpoint(route, :socks5) do
      # Disable shared HTTP pooling: identical URLs can exist in different
      # organizations, and a pooled socket must never cross tailnet boundaries.
      {:ok,
       [
         with_body: true,
         pool: false,
         proxy: {:socks5, "127.0.0.1", port},
         socks5_resolve: :remote
       ]}
    end
  end

  def route(database, kind) do
    connection_id =
      if kind == :database,
        do: database.network_connection_id,
        else: database.trace_network_connection_id

    with {:ok, connection} <-
           NetworkConnections.available(database.organization_id, connection_id),
         {:ok, host, port} <- destination(database, kind),
         {:ok, _} <- NetworkConnections.client().configure(connection) do
      route = %{
        organization_id: database.organization_id,
        connection_id: connection.id,
        generation: connection.generation,
        resource_id: database.id,
        version: database.pool_version || 1,
        kind: to_string(kind),
        host: host,
        port: port
      }

      with {:ok, _} <- NetworkConnections.client().put_route(route), do: {:ok, route}
    end
  end

  defp destination(database, :database) do
    {:ok, database.host,
     database.port || Trifle.Organizations.Database.default_port(database.driver)}
  end

  defp destination(database, :s3) do
    uri = URI.parse(database.trace_config["data_endpoint"] || "")

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and is_nil(uri.userinfo),
      do: {:ok, uri.host, uri.port},
      else: {:error, :invalid_private_s3_endpoint}
  end
end
