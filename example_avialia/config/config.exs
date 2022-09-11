# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :example_avialia,
  ecto_repos: [ExampleAvialia.BoardingsRepo, ExampleAvialia.CargosRepo]

# Configures the endpoint
config :example_avialia, ExampleAvialiaWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "+8HFIKSonS0sCSYGxWsCitG//mjSX+yGYO/OPJsnuusimWr0NP7AKk5ivn6PDb46",
  render_errors: [view: ExampleAvialiaWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: ExampleAvialia.PubSub,
  live_view: [signing_salt: "sseZBpRJ"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
