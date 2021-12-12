# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :exchange,
  ecto_repos: [Exchange.Repo],
  event_stores: [Exchange.EventStore],
  generators: [binary_id: true]

# Configures the endpoint
config :exchange, ExchangeWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "75OxDABuRWcvgrjTtCvb9SAFKIo6fWIkuompr/KP1yGI9GV9GOg0PAwSs+RXAl+s",
  render_errors: [view: ExchangeWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Exchange.PubSub,
  live_view: [signing_salt: "HzHnAWSK"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  level: :info

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
