defmodule Domo.MixProjectHelper do
  @moduledoc false

  @skip_test_env_check_key_name :skip_test_env_check

  def disable_raise_in_test_env, do: Application.put_env(:domo, @skip_test_env_check_key_name, true)
  def enable_raise_in_test_env, do: Application.delete_env(:domo, @skip_test_env_check_key_name)

  def global_stub(project_configuration \\ Mix.Project.config()) do
    project_configuration[:app] == :domo && project_configuration[:mix_project_stub]
  end

  def opts_stub(opts, caller_env) do
    opts
    |> Keyword.get(:mix_project_stub)
    |> Macro.expand_once(caller_env)
  end
end
