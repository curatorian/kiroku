# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :kiroku,
  ecto_repos: [Kiroku.Repo],
  generators: [timestamp_type: :utc_datetime],
  institution_name: "Universitas Padjadjaran",
  institution_domain: "unpad.ac.id"

# Oban background job processing
embargo_cron = System.get_env("EMBARGO_CRON", "0 2 * * *")

config :kiroku, Oban,
  repo: Kiroku.Repo,
  queues: [default: 10, embargo: 2, notifications: 5],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron,
     crontab: [
       {embargo_cron, Kiroku.Embargo.LifterWorker}
     ]}
  ]

# Configure the endpoint
config :kiroku, KirokuWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: KirokuWeb.ErrorHTML, json: KirokuWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Kiroku.PubSub,
  live_view: [signing_salt: "mCUE+WqT"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :kiroku, Kiroku.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  kiroku: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  kiroku: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
