defmodule Trifle.Networking.DatabaseTLS do
  @moduledoc false

  def enabled?(config), do: (config || %{})["ssl"] in [true, "true"]

  def options(host) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(host),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]
  end

  def postgres(options, %{connection_method: "tailscale"} = database) do
    if enabled?(database.config),
      do: Keyword.put(options, :ssl, options(database.host)),
      else: options
  end

  def postgres(options, _database), do: options

  def mysql(options, %{connection_method: "tailscale"} = database) do
    if enabled?(database.config),
      do: Keyword.put(options, :ssl_opts, options(database.host)),
      else: options
  end

  def mysql(options, _database), do: options

  def mongo(options, %{connection_method: "tailscale"} = database) do
    options = Keyword.put(options, :type, :single)

    if enabled?(database.config),
      do: options |> Keyword.put(:ssl, true) |> Keyword.put(:ssl_opts, options(database.host)),
      else: options
  end

  def mongo(options, database) do
    if enabled?(database.config),
      do: options |> Keyword.put(:ssl, true) |> Keyword.put(:ssl_opts, options(database.host)),
      else: options
  end

  def redis(options, database) do
    if enabled?(database.config) do
      options
      |> Keyword.put(:ssl, true)
      |> Keyword.update(:socket_opts, options(database.host), &(options(database.host) ++ &1))
    else
      options
    end
  end
end
