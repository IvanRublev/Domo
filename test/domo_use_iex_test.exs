defmodule DomoUseIexTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.Raises
  alias Domo.TypeEnsurerFactory
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias ModuleTypes

  @treat_as_any_optional_lib_modules [Ecto.Schema.Metadata]

  @moduletag in_mix_compile?: false

  setup tags do
    ResolverTestHelper.disable_raise_in_test_env()
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: tags.in_mix_compile?

    Code.compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)

    if tags.in_mix_compile? do
      DomoMixTask.start_plan_collection()
    end

    on_exit(fn ->
      if tags.in_mix_compile? do
        DomoMixTask.stop_plan_collection()
      end

      ResolverTestHelper.enable_raise_in_test_env()
    end)

    %{
      plan_path: :in_memory,
      preconds_path: :in_memory
    }
  end

  describe "use Domo in general should" do
    setup do
      allow MixProjectStubCorrect.config(), meck_options: [:passthrough], return: []
      allow TypeEnsurerFactory.start_resolve_planner(any(), any(), any()), return: {:ok, self()}
      allow TypeEnsurerFactory.plan_struct_defaults_ensurance(any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_to_treat_as_any(any(), any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok
      allow Domo._build_in_memory_type_ensurer(any(), any()), meck_options: [:passthrough], return: :ok
      allow TypeEnsurerFactory.type_ensurer(any()), return: Module.TypeEnsurer
      allow TypeEnsurerFactory.module_name_string(any()), return: "Module.TypeEnsurer"
      allow TypeEnsurerFactory.plan_precond_checks(any(), any(), any()), return: :ok
      :ok
    end

    test "Not ensure compiler location in project's compilers list executed Not with `mix compile` but f.e. with iex" do
      defmodule Module do
        use Domo

        defstruct []
        @type t :: %__MODULE__{}
      end

      defmodule SharedKernel do
        import Domo

        @type id :: String.t()
        precond id: &(&1 != "")
      end
    end

    test "start ResolvePlanner", %{plan_path: plan_path, preconds_path: preconds_path} do
      defmodule Module do
        use Domo

        defstruct []
        @type t :: %__MODULE__{}
      end

      assert_called TypeEnsurerFactory.start_resolve_planner(plan_path, preconds_path, any())
    end

    test "collect types to treat as Any passed locally", %{plan_path: plan_path} do
      defmodule Module do
        use Domo, remote_types_as_any: [{Module, [:t]}]

        defstruct []
        @type t :: %__MODULE__{}
      end

      assert_called TypeEnsurerFactory.collect_types_to_treat_as_any(plan_path, Module, any(), [{Module, [:t]}])
    end

    test "collect types for Domo compiler", %{plan_path: plan_path} do
      defmodule Module do
        use Domo, skip_defaults: true

        defstruct [:id]
        @type t :: %__MODULE__{id: integer()}
      end

      assert_called TypeEnsurerFactory.collect_types_for_domo_compiler(plan_path, is(&(&1.module == Module)), any())
    end

    test "build in memory only TypeEnsurer after compile" do
      defmodule Module do
        use Domo, skip_defaults: true

        defstruct [:id]
        @type t :: %__MODULE__{id: integer()}
      end

      assert_called Domo._build_in_memory_type_ensurer(is(&(&1.module == Module)), any())
    end

    @tag in_mix_compile?: true
    test "Not build in memory only TypeEnsurer if not in iex" do
      allow Raises.maybe_raise_absence_of_domo_compiler!(any(), any()), meck_options: [:passthrough], return: :ok

      defmodule Module do
        use Domo, skip_defaults: true

        defstruct [:id]
        @type t :: %__MODULE__{id: integer()}
      end

      refute_called(TypeEnsurerFactory.build_in_memory_type_ensurer(any()))
    end

    test "Not plan struct integrity ensurance by calling new!" do
      allow TypeEnsurerFactory.plan_struct_integrity_ensurance(any(), any(), any()), return: :ok

      CustomStructUsingDomo.new!(title: nil)
      refute_called(TypeEnsurerFactory.plan_struct_integrity_ensurance(any(), any(), any()))

      CustomStructUsingDomo.new(title: nil)
      refute_called(TypeEnsurerFactory.plan_struct_integrity_ensurance(any(), any(), any()))
    end
  end

  describe "To build in memory TypeEnsurer after compile Domo should" do
    setup do
      allow ResolvePlanner.plan_types_resolving(any(), any(), any(), any()), meck_options: [:passthrough], return: :ok
      allow ResolvePlanner.keep_module_environment(any(), any(), any()), meck_options: [:passthrough], return: :ok
      allow ResolvePlanner.keep_global_remote_types_to_treat_as_any(any(), any()), meck_options: [:passthrough], return: :ok
      allow ModuleInspector.ensure_loaded?(any()), meck_options: [:passthrough], return: true
      allow ModuleInspector.has_type_ensurer?(any()), meck_options: [:passthrough], return: false
      allow TypeEnsurerFactory.register_in_memory_types(any(), any()), meck_options: [:passthrough], return: :ok
      allow TypeEnsurerFactory.clean_plan(any()), return: :ok

      TypeEnsurerFactory.start_resolve_planner(:in_memory, :in_memory, [])
      on_exit(fn -> ResolverTestHelper.stop_in_memory_planner() end)

      {:module, _, bytecode, _} =
        defmodule Module do
          def env, do: __ENV__
        end

      env = Module.env()

      %{env: env, bytecode: bytecode}
    end

    test "collect types to treat as any", %{env: env, bytecode: bytecode} do
      Domo._build_in_memory_type_ensurer(env, bytecode)

      expected_types = @treat_as_any_optional_lib_modules |> Enum.map(&{&1, [:t]}) |> Enum.into(%{})
      assert_called ResolvePlanner.keep_global_remote_types_to_treat_as_any(:in_memory, expected_types)
    end

    test "register module types for resolves in depending in memory modules", %{env: env, bytecode: bytecode} do
      Domo._build_in_memory_type_ensurer(env, bytecode)

      assert_called TypeEnsurerFactory.register_in_memory_types(__MODULE__.Module, bytecode)
    end

    test "clean plan after building of TypeEnsurers" do
      defmodule Module do
        use Domo, skip_defaults: true

        defstruct [:id]
        @type t :: %__MODULE__{id: integer()}
      end

      assert_called TypeEnsurerFactory.clean_plan(:in_memory)
    end
  end
end
