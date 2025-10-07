import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/trifle start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :trifle, TrifleWeb.Endpoint, server: true
end

deployment_mode =
  case System.get_env("TRIFLE_DEPLOYMENT_MODE") do
    mode when mode in ["self_hosted", "self-hosted", "selfhosted"] -> :self_hosted
    mode when mode in ["saas", "SaaS"] -> :saas
    _ -> Application.get_env(:trifle, :deployment_mode, :saas)
  end

config :trifle, :deployment_mode, deployment_mode

projects_enabled =
  case System.get_env("TRIFLE_PROJECTS_ENABLED") do
    nil -> Application.get_env(:trifle, :projects_enabled, true)
    "" -> Application.get_env(:trifle, :projects_enabled, true)
    value ->
      case String.downcase(value) do
        v when v in ["1", "true", "yes", "on", "enabled"] -> true
        v when v in ["0", "false", "no", "off", "disabled"] -> false
        _ -> Application.get_env(:trifle, :projects_enabled, true)
      end
  end

config :trifle, :projects_enabled, projects_enabled

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :trifle, Trifle.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :trifle, TrifleWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :trifle, TrifleWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :trifle, TrifleWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  mailer_from_name = System.get_env("MAILER_FROM_NAME") || "Trifle"
  mailer_from_email = System.get_env("MAILER_FROM_EMAIL") || "contact@example.com"

  config :trifle, :mailer_from, {mailer_from_name, mailer_from_email}

  mailer_adapter =
    System.get_env("MAILER_ADAPTER", "local")
    |> String.downcase()

  to_int = fn value, default ->
    case value do
      nil -> default
      "" -> default
      v -> String.to_integer(v)
    end
  end

  truthy? = fn value, default ->
    case value do
      nil -> default
      "" -> default
      v when v in ["1", "true", "TRUE", "yes", "on", "enabled"] -> true
      v when v in ["0", "false", "FALSE", "no", "off", "disabled"] -> false
      _ -> default
    end
  end

  parse_setting = fn value, default ->
    case value do
      nil ->
        default

      "" ->
        default

      v ->
        case String.downcase(v) do
          "always" -> :always
          "never" -> :never
          _ -> default
        end
    end
  end

  configure_api_client = fn ->
    config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Trifle.Finch
  end

  case mailer_adapter do
    "local" ->
      config :trifle, Trifle.Mailer, adapter: Swoosh.Adapters.Local
      config :swoosh, api_client: false, finch_name: nil

    "smtp" ->
      relay =
        System.get_env("SMTP_RELAY") ||
          raise "MAILER_ADAPTER=smtp requires SMTP_RELAY to be set"

      smtp_opts =
        [
          adapter: Swoosh.Adapters.SMTP,
          relay: relay,
          username: System.get_env("SMTP_USERNAME"),
          password: System.get_env("SMTP_PASSWORD"),
          port: to_int.(System.get_env("SMTP_PORT"), 587),
          tls: parse_setting.(System.get_env("SMTP_TLS"), :if_available),
          ssl: truthy?.(System.get_env("SMTP_SSL"), false),
          auth: parse_setting.(System.get_env("SMTP_AUTH"), :if_available),
          retries: to_int.(System.get_env("SMTP_RETRIES"), nil)
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      config :trifle, Trifle.Mailer, smtp_opts
      config :swoosh, api_client: false, finch_name: nil

    "postmark" ->
      api_key =
        System.get_env("POSTMARK_API_KEY") ||
          raise "MAILER_ADAPTER=postmark requires POSTMARK_API_KEY"

      config :trifle, Trifle.Mailer,
        adapter: Swoosh.Adapters.Postmark,
        api_key: api_key

      configure_api_client.()

    "sendgrid" ->
      api_key =
        System.get_env("SENDGRID_API_KEY") ||
          raise "MAILER_ADAPTER=sendgrid requires SENDGRID_API_KEY"

      config :trifle, Trifle.Mailer,
        adapter: Swoosh.Adapters.Sendgrid,
        api_key: api_key

      configure_api_client.()

    "mailgun" ->
      api_key =
        System.get_env("MAILGUN_API_KEY") ||
          raise "MAILER_ADAPTER=mailgun requires MAILGUN_API_KEY"

      domain =
        System.get_env("MAILGUN_DOMAIN") ||
          raise "MAILER_ADAPTER=mailgun requires MAILGUN_DOMAIN"

      opts =
        [
          adapter: Swoosh.Adapters.Mailgun,
          api_key: api_key,
          domain: domain
        ] ++
          case System.get_env("MAILGUN_BASE_URL") do
            value when value in [nil, ""] -> []
            value -> [base_url: value]
          end

      config :trifle, Trifle.Mailer, opts
      configure_api_client.()

    adapter when adapter in ["sendinblue", "brevo"] ->
      api_key =
        System.get_env("SENDINBLUE_API_KEY") ||
          System.get_env("BREVO_API_KEY") ||
          raise "MAILER_ADAPTER=#{adapter} requires SENDINBLUE_API_KEY (or BREVO_API_KEY)"

      config :trifle, Trifle.Mailer,
        adapter: Swoosh.Adapters.Sendinblue,
        api_key: api_key

      configure_api_client.()

    other ->
      raise ArgumentError,
            "Unsupported MAILER_ADAPTER '#{other}'. Valid options: local, smtp, postmark, sendgrid, mailgun, sendinblue/brevo."
  end
end
