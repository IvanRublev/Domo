# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :domo, :test_structs_path, "test/struct_modules"

if Mix.env() == :test do
  config :domo, :mix_project, MixProjectStubCorrect
end
