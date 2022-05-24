defmodule Mix.Tasks.Compile.DomoPhoenixHotReload do
  @moduledoc false

  use Mix.Task.Compiler

  alias Domo.CodeEvaluation
  alias Domo.Raises
  alias Mix.Tasks.Compile.DomoCompiler
  alias Mix.TasksServer

  @impl true
  def run(args) do
    unless elixir_run?() do
      Raises.raise_no_elixir_compiler_was_run()
    end

    if CodeEvaluation.in_plan_collection?() do
      # In case of compile.all mix task the plan is processed automatically
      # in :after_compile hook. That is not the case with Phoenix hot-reload
      # which calls each compiler's mix task directly that eventually keeps :after_compile
      # hook intact and stays in plan collection mode forever.
      DomoCompiler.process_plan(:ok, args)
    else
      {:noop, []}
    end
  end

  defp elixir_run? do
    project = Mix.Project.get()
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
