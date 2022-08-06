# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :domo, :test_structs_path, "test/struct_modules"

if config_env() == :test do
  config :domo, :mix_project, MixProjectStubCorrect
end
