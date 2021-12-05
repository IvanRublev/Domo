defmodule Domo.InteractiveTypeRegistrationTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory

  @moduletag in_mix_compile?: false

  setup tags do
    ResolverTestHelper.disable_raise_in_test_env()
    allow CodeEvaluation.in_mix_compile?(any()), meck_options: [:passthrough], return: tags.in_mix_compile?

    Code.compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
      ResolverTestHelper.enable_raise_in_test_env()
    end)

    :ok
  end

  describe "Interactive type registration in iex should" do
    setup do
      allow TypeEnsurerFactory.start_resolve_planner(any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.register_in_memory_types(any(), any()), return: :ok
      allow TypeEnsurerFactory.get_dependants(any(), any()), return: {:ok, []}
      :ok
    end

    test "start ResolvePlanner" do
      defmodule ModuleMemoryTypes do
        use Domo.InteractiveTypesRegistration
        @type id :: integer()
      end

      assert_called TypeEnsurerFactory.start_resolve_planner(:in_memory, :in_memory, any())
    end

    test "register types in iex" do
      {:module, _, bytecode, _} =
        defmodule ModuleMemoryTypes do
          use Domo.InteractiveTypesRegistration

          @type id :: integer()
        end

      assert_called TypeEnsurerFactory.register_in_memory_types(ModuleMemoryTypes, bytecode)
    end
  end

  @tag in_mix_compile?: true
  test "Interactive type registration in mix compile raises an error" do
    assert_raise CompileError, ~r/Domo.InteractiveTypesRegistration should be used only in interactive elixir./, fn ->
      defmodule ModuleMemoryTypes do
        use Domo.InteractiveTypesRegistration

        @type id :: integer()
      end
    end
  end
end
