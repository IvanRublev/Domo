defmodule Domo.MixTasksCompileDomoPhoenixHotReloadTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Mix.Tasks.Compile.DomoCompiler
  alias Mix.Tasks.Compile.DomoPhoenixHotReload, as: DomoPhoenixMixTask
  alias Mix.TasksServer

  @domo_phoenix_hot_reload_compiler_error_regex Regex.compile!("""
                                                :elixir compiler wasn't run. Please, check if :domo_phoenix_hot_reload \
                                                is placed after :elixir in the compilers list in the mix.exs file and \
                                                in reloadable_compilers list in the configuration file.\
                                                """)

  setup do
    ResolverTestHelper.disable_raise_in_test_env()
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true

    Code.compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
      ResolverTestHelper.enable_raise_in_test_env()

      Placebo.unstub()
    end)

    :ok
  end

  describe "Domo compiler phoenix hot reload task should" do
    @moduletag in_plan_collection?: true
    @moduletag compile_elixir_run?: true
    @moduletag project_config: [compilers: [:domo_compiler, :elixir, :domo_phoenix_hot_reload]]

    setup tags do
      allow CodeEvaluation.in_plan_collection?(), meck_options: [:passthrough], return: tags.in_plan_collection?
      allow DomoCompiler.process_plan(any(), any()), return: {:noop, []}

      if function_exported?(TasksServer, :get, 1) do
        allow TasksServer.get({:task, "compile.elixir", any()}), meck_options: [:passthrough], return: tags.compile_elixir_run?
      else
        allow Agent.get(Mix.TasksServer, any(), any()), meck_options: [:passthrough], return: tags.compile_elixir_run?
      end

      allow MixProjectStubCorrect.config(), meck_options: [:passthrough], return: tags.project_config

      :ok
    end

    test "process plan being in collection mode" do
      DomoPhoenixMixTask.run(:ok)

      assert_called DomoCompiler.process_plan(any(), any())
    end

    @tag project_config: []
    test "skip running having no the compiler in compilers list (umbrella case)" do
      DomoPhoenixMixTask.run(:ok)

      refute_called DomoCompiler.process_plan(any(), any())
    end

    @tag in_plan_collection?: false
    test "Not process plan being Not in collection mode" do
      DomoPhoenixMixTask.run(:ok)

      refute_called DomoCompiler.process_plan(any(), any())
    end

    test "raise No exception having elixir compiler executed before" do
      DomoPhoenixMixTask.run(:ok)
    end

    @tag compile_elixir_run?: false
    test "raise exception having No elixir compiler executed before" do
      assert_raise CompileError, @domo_phoenix_hot_reload_compiler_error_regex, fn ->
        DomoPhoenixMixTask.run(:ok)
      end
    end
  end
end
