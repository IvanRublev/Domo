defmodule Domo.TypeEnsurerFactory.DependencyResolver.ElixirTask do
  @moduledoc false

  def recompile_with_elixir(verbose?) do
    command = Mix.Utils.module_name_to_command("Mix.Tasks.Compile.Elixir", 2)

    opts = if verbose?, do: ["--verbose"], else: []

    Mix.Task.rerun(command, opts)
  end
end
