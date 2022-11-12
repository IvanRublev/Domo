defmodule Mix.Tasks.Compile.DomoPhoenixHotReload do
  @moduledoc """
  The module to process domo plan into type ensurers.

  In case of compile.all mix task the plan is processed automatically
  in :after_compile hook. That is not the case with Phoenix hot-reload
  which calls each compiler's mix task directly that eventually keeps :after_compile
  hook intact and stays in plan collection mode forever.

  The :domo_phoenix_hot_reload compiler process plan on execution.
  """

  use Mix.Task.Compiler

  alias Domo.CodeEvaluation
  alias Domo.Raises
  alias Mix.Tasks.Compile.DomoCompiler
  alias Mix.TasksServer

  @mix_project Application.compile_env(:domo, :mix_project, Mix.Project)

  @impl true
  def run(args) do
    cond do
      not hot_reload_compiler_in_project?() -> {:noop, []}
      not elixir_run_before?() -> Raises.raise_no_elixir_compiler_was_run()
      CodeEvaluation.in_plan_collection?() -> DomoCompiler.process_plan(:ok, args)
      true -> {:noop, []}
    end
  end

  defp hot_reload_compiler_in_project? do
    compilers = get_in(@mix_project.config(), [:compilers]) || []
    Enum.member?(compilers, :domo_phoenix_hot_reload)
  end

  defp elixir_run_before? do
    project = @mix_project.get()
    elixir_command = Mix.Task.task_name(Mix.Tasks.Compile.Elixir)
    tuple = {:task, elixir_command, project}

    if function_exported?(TasksServer, :get, 1) do
      TasksServer.get(tuple)
    else
      # There is no function before Elixir v1.11.2
      Agent.get(TasksServer, &Map.get(&1, tuple), :infinity)
    end
  end
end
