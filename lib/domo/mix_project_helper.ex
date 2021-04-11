defmodule Domo.MixProjectHelper do
  @moduledoc false

  def global_stub(project_configuration \\ Mix.Project.config()) do
    project_configuration[:app] == :domo && project_configuration[:mix_project_stub]
  end

  def opts_stub(opts, caller_env) do
    opts
    |> Keyword.get(:mix_project_stub)
    |> Macro.expand_once(caller_env)
  end
end
