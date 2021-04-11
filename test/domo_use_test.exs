defmodule DomoUseTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.MixProjectHelper
  alias Mix.Tasks.Compile.Domo, as: DomoMixTask
  alias ModuleTypes

  def env, do: __ENV__

  defp module_empty do
    {:module, _, _bytecode, _} =
      defmodule Module do
        use Domo

        defstruct []
        @type t :: %__MODULE__{}
      end
  end

  defp module_two_fields do
    {:module, _, _bytecode, _} =
      defmodule Module do
        use Domo

        defstruct [:first, second: 1.0]
        @type t :: %__MODULE__{first: atom, second: float}
      end
  end

  defp module1_one_field do
    {:module, _, _bytecode, _} =
      defmodule Module1 do
        use Domo

        defstruct [:former]
        @type t :: %__MODULE__{former: integer}
      end
  end

  setup do
    Code.compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)

    project = MixProjectHelper.global_stub()
    plan_file = DomoMixTask.manifest_path(project, :plan)
    types_file = DomoMixTask.manifest_path(project, :types)
    deps_file = DomoMixTask.manifest_path(project, :deps)
    code_path = DomoMixTask.generated_code_path(project)

    on_exit(fn ->
      ResolvePlanner.stop(plan_file)
    end)

    %{plan_file: plan_file, types_file: types_file, deps_file: deps_file, code_path: code_path}
  end

  describe "use Domo should" do
    test "ensure the its compiler location is after elixir in project's compilers list" do
      expected_message =
        Regex.compile!("""
        Domo should be included after the :elixir in the compilers list \
        in the project's configuration mix.exs file because it launches \
        the second-pass of the compilation to resolve remote types \
        that are in project BEAM files.
        The mix.exs should have project\\/0 function returning a list \
        with the following key compilers: \
        Mix.compilers\\(\\) \\+\\+ \\[:domo\\] where the :domo \
        location is after the :elixir compiler.\
        """)

      assert_raise CompileError, expected_message, fn ->
        defmodule Module do
          use Domo, mix_project_stub: MixProjectStubEmpty

          defstruct []
          @type t :: %__MODULE__{}
        end
      end

      assert_raise CompileError, expected_message, fn ->
        defmodule Module do
          use Domo, mix_project_stub: MixProjectStubWrongCompilersOrder

          defstruct []
          @type t :: %__MODULE__{}
        end
      end

      module =
        defmodule Module do
          use Domo, mix_project_stub: MixProjectStubCorrect

          defstruct []
          @type t :: %__MODULE__{}
        end

      assert {:module, _, _bytecode, _} = module
    end

    test "raise CompileError when it's outside of the module scope" do
      assert_raise CompileError,
                   "nofile: use Domo should be called in a module scope only. To have tagged tuple functions try use Domo.TaggedTuple instead.",
                   fn ->
                     Code.compile_quoted(quote(do: use(Domo)))
                   end

      assert_raise CompileError,
                   "nofile: use Domo should be called in a module scope only. To have tagged tuple functions try use Domo.TaggedTuple instead.",
                   fn ->
                     Code.compile_quoted(
                       quote do
                         defmodule M do
                           def fff do
                             use Domo, mix_project: MixProjectStubCorrect
                           end
                         end
                       end
                     )
                   end
    end

    test "raise CompileError when it's in a module lacking defstruct" do
      assert_raise CompileError,
                   Regex.compile!("""
                   use Domo should be called from within the module \
                   defining a struct.
                   """),
                   fn ->
                     defmodule Module do
                       use Domo
                     end
                   end
    end

    test "raise the error for missing t() of struct type for the module" do
      message =
        Regex.compile!("""
        Type t\\(\\) should be defined for the struct \
        #{inspect(__MODULE__)}.Module, that enables Domo \
        to generate type ensurer module for the struct's data.\
        """)

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]
          end
      end

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]

            @type t :: atom()
          end
      end

      module1_one_field()

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]

            @type t :: %Module1{}
          end
      end
    end

    test "Not raise when t is defined alongside with other types" do
      module =
        defmodule Module do
          use Domo

          @enforce_keys [:name, :title]
          defstruct [:name, :title]

          @type name :: String.t()
          @type title :: String.t()
          @type t :: %__MODULE__{name: name(), title: title()}
        end

      assert {:module, _, _bytecode, _} = module
    end

    test "generate dummy TypeEnsurer module to make dependant new/merge/put functions be compiled" do
      module_two_fields()

      assert true == Code.ensure_loaded?(__MODULE__.Module.TypeEnsurer)
      assert Kernel.function_exported?(__MODULE__.Module.TypeEnsurer, :ensure_type!, 1)

      assert_raise RuntimeError,
                   """
                   The #{inspect(__MODULE__.Module.TypeEnsurer)} module implementation should be generated by Domo. \
                   Please, ensure that :domo compiler is included after the :elixir \
                   in the compilers list in the project's configuration mix.exs file.
                   """,
                   fn ->
                     apply(__MODULE__.Module.TypeEnsurer, :ensure_type!, [:foo])
                   end
    end
  end

  describe "Domo after compile of the module should" do
    setup do
      allow ResolvePlanner.ensure_started(any()), return: {:ok, self()}
      allow ResolvePlanner.keep_module_environment(any(), any(), any()), return: :ok
      allow ResolvePlanner.plan_types_resolving(any(), any(), any(), any()), return: :ok
      allow ResolvePlanner.flush(any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok

      :ok
    end

    test "generate specs for structure functions" do
      module =
        defmodule Module do
          use Domo

          @enforce_keys []
          defstruct []

          @type t :: %__MODULE__{}
        end

      {:module, _, bytecode, _} = module

      assert """
             [ensure_type!(t()) :: t(), \
             ensure_type_ok(t()) :: {:ok, t()} | {:error, term()}, \
             new(Enum.t()) :: t(), \
             new_ok(Enum.t()) :: t()]\
             """ ==
               bytecode
               |> ModuleTypes.specs()
               |> ModuleTypes.specs_to_string()
    end

    test "Not generate specs if no_specs option is given" do
      module =
        defmodule Module do
          use Domo, no_specs: true

          @enforce_keys []
          defstruct []

          @type t :: %__MODULE__{}
        end

      {:module, _, bytecode, _} = module

      assert "[]" ==
               bytecode
               |> ModuleTypes.specs()
               |> ModuleTypes.specs_to_string()
    end

    test "start the ResolvePlanner" do
      module_empty()

      assert_called ResolvePlanner.ensure_started(any())
    end

    test "keep the module environment for further type resolvance" do
      module_empty()

      expected_module = __MODULE__.Module

      assert_called ResolvePlanner.keep_module_environment(
                      any(),
                      expected_module,
                      is(fn env -> env.module == expected_module end)
                    )
    end

    test "plan the resolvance of each field type of the struct, plain and with default value" do
      module_two_fields()

      expected_module = __MODULE__.Module

      assert_called ResolvePlanner.plan_types_resolving(
                      any(),
                      expected_module,
                      :first,
                      is(fn {:atom, _, _} -> true end)
                    )

      assert_called ResolvePlanner.plan_types_resolving(
                      any(),
                      expected_module,
                      :second,
                      is(fn {:float, _, _} -> true end)
                    )
    end

    test "flush the plan to disk as the last step" do
      module_two_fields()

      assert {_, {Domo.TypeEnsurerFactory.ResolvePlanner, :flush, _}, _} =
               List.last(:meck.history(ResolvePlanner))
    end
  end
end
