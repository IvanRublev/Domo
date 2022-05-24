defmodule Domo.TypeEnsurerFactory.DependencyResolver.ElixirTask do
  @moduledoc false

  def recompile_with_elixir(verbose?) do
    command = Mix.Task.task_name(Mix.Tasks.Compile.Elixir)

    opts = if verbose?, do: ["--verbose"], else: []

    Mix.Task.rerun(command, opts)
  end
end
