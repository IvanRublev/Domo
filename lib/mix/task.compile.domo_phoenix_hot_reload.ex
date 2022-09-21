defmodule Mix.Tasks.Compile.DomoPhoenixHotReload do
  @moduledoc false

  use Mix.Task.Compiler

  alias Domo.CodeEvaluation
  alias Domo.Raises
  alias Mix.Tasks.Compile.DomoCompiler
  alias Mix.TasksServer

  @impl Mix.Task.Compiler
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
    Enum.all?(domo_hot_reload_projects(), &elixir_run?/1)
  end

  defp domo_hot_reload_projects do
    project = Mix.Project.get()

    if Mix.Project.umbrella?() do
      Mix.Project.apps_paths()
      |> Enum.to_list()
      |> Enum.map(fn {app, app_path} ->
        Mix.Project.in_project(app, app_path, fn project ->
          if uses_this_compiler?(project) do
            project
          else
            nil
          end
        end)
      end)
      |> Enum.reject(&is_nil/1)
    else
      [project]
    end
  end

  defp uses_this_compiler?(project) do
    compiler_name = Macro.underscore(__MODULE__)
    project_compilers = Keyword.get(project.project(), :compilers, [])

    compiler_name in project_compilers
  end

  defp elixir_run?(project) do
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
