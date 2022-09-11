# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :benchmark_ecto_domo,
  ecto_repos: [BenchmarkEctoDomo.Repo]

# Configure your database
config :benchmark_ecto_domo, BenchmarkEctoDomo.Repo,
  username: "postgres",
  password: "postgres",
  database: "benchmark_ecto_domo",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10
