use Mix.Config

# Configure your database
config :app, App.Repo,
  username: "postgres",
  password: "postgres",
  database: "example_app_test",
  hostname: "localhost",
  port: 15678,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :app, AppWeb.Endpoint,
  http: [port: 4002],
  server: false

# Print only warnings and errors during test
config :logger, level: :warn
