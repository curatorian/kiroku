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
#     PHX_SERVER=true bin/kiroku start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :kiroku, KirokuWeb.Endpoint, server: true
end

config :kiroku, KirokuWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  # MSSQL legacy read-only import database (import-time only)
  #
  # The entire sync/MSSQL feature is OPTIONAL. When MSSQL_HOST is not set,
  # the legacy repo config is skipped, Oban sync cron jobs are excluded,
  # and the UI hides sync-related sections. Set MSSQL_HOST and related
  # vars only if you need to import from a legacy MSSQL database.
  if System.get_env("MSSQL_HOST") not in [nil, ""] do
    config :kiroku, Kiroku.LegacyRepo,
      adapter: Ecto.Adapters.Tds,
      hostname: System.get_env("MSSQL_HOST"),
      database: System.get_env("MSSQL_DB"),
      username: System.get_env("MSSQL_USER"),
      password: System.get_env("MSSQL_PASS"),
      port: String.to_integer(System.get_env("MSSQL_PORT", "1433")),
      pool_size: 2
  end

  # Rebuild Oban crontab at runtime so releases respect MSSQL_HOST
  embargo_cron = System.get_env("EMBARGO_CRON", "0 2 * * *")
  sync_cron = System.get_env("SYNC_CRON", "0 */6 * * *")

  sync_crontab =
    if System.get_env("MSSQL_HOST") not in [nil, ""] do
      [
        {sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Skripsi"}},
        {sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Tesis"}},
        {sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Disertasi"}},
        {sync_cron, Kiroku.Workers.MssqlSyncWorker, args: %{"view" => "Tugas-Akhir"}}
      ]
    else
      []
    end

  config :kiroku, Oban,
    plugins: [
      {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
      {Oban.Plugins.Cron, crontab: [{embargo_cron, Kiroku.Embargo.LifterWorker} | sync_crontab]}
    ]

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Encrypt the database connection. Strongly recommended when Postgres is
  # reached over a network (e.g. a separate database VM). Defaults to true
  # to avoid leaking credentials/data over the wire; set ECTO_DB_SSL=false
  # to disable (e.g. loopback, or a DB that does not support TLS).
  db_ssl? = System.get_env("ECTO_DB_SSL") not in ~w(false 0)

  config :kiroku, Kiroku.Repo,
    url: database_url,
    ssl: db_ssl?,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
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

  config :kiroku, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :kiroku, KirokuWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :kiroku, KirokuWeb.Endpoint,
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
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :kiroku, KirokuWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :kiroku, Kiroku.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
