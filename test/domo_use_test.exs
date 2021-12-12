defmodule DomoUseTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.CodeEvaluation
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias ModuleTypes

  @no_domo_compiler_error_regex Regex.compile!("""
                                Domo compiler is expected to do a second-pass compilation \
                                to resolve remote types that are in the project's BEAM files \
                                and generate TypeEnsurer modules.
                                """)

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

  defp module_custom_struct_as_default_value do
    {:module, _, _bytecode, _} =
      defmodule Module do
        defmodule Submodule do
          use Domo
          defstruct [:title]
          @type t :: %__MODULE__{title: String.t()}
        end

        defstruct field: Submodule.new!(title: "string")
        @type t :: %__MODULE__{field: Submodule.t()}
      end
  end

  defp module_with_precond do
    {:module, _, _bytecode, _} =
      defmodule Module do
        defmodule Ext do
          def value_valid?(_value), do: true
        end

        use Domo

        defstruct field: 1.0

        @type counter :: integer
        precond counter: &(&1 != 0)

        @type value :: atom
        precond value: &Ext.value_valid?/1

        @type t :: %__MODULE__{field: float}
        precond t: fn %{field: field} -> field > 0.5 end
      end
  end

  @moduletag in_mix_compile?: true
  @moduletag in_mix_test?: false

  setup tags do
    ResolverTestHelper.disable_raise_in_test_env()
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: tags.in_mix_compile?
    allow CodeEvaluation.in_mix_test?(), meck_options: [:passthrough], return: tags.in_mix_test?

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

    :ok
  end

  describe "use Domo should" do
    test "ensure its compiler location is before elixir in project's compilers list executed with `mix compile`" do
      allow MixProjectStubCorrect.config(), meck_options: [:passthrough], return: []

      assert_raise CompileError, @no_domo_compiler_error_regex, fn ->
        defmodule Module do
          use Domo

          defstruct []
          @type t :: %__MODULE__{}
        end
      end

      allow MixProjectStubCorrect.config(), meck_options: [:passthrough], return: [compilers: [:elixir, :domo_compiler]]

      assert_raise CompileError, @no_domo_compiler_error_regex, fn ->
        defmodule Module do
          use Domo

          defstruct []
          @type t :: %__MODULE__{}
        end
      end

      allow MixProjectStubCorrect.config(), meck_options: [:passthrough], return: []

      assert_raise CompileError, @no_domo_compiler_error_regex, fn ->
        defmodule SharedKernel do
          import Domo

          @type id :: String.t()
          precond id: &(&1 != "")
        end
      end

      allow MixProjectStubCorrect.config(), meck_options: [:passthrough], return: [compilers: [:domo_compiler, :elixir]]

      module =
        defmodule SharedKernel do
          import Domo

          @type id :: String.t()
          precond id: &(&1 != "")
        end

      assert {:module, _, _bytecode, _} = module

      module =
        defmodule Module do
          use Domo

          defstruct []
          @type t :: %__MODULE__{}
        end

      assert {:module, _, _bytecode, _} = module
    end

    @tag in_mix_compile?: false
    @tag in_mix_test?: true
    test "raise an exception in test environment" do
      ResolverTestHelper.enable_raise_in_test_env()

      plan_path = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)
      preconds_path = DomoMixTask.manifest_path(MixProjectStubCorrect, :preconds)

      assert_raise RuntimeError,
                   """
                   Domo can't build TypeEnsurer module in the test environment for DomoUseTest.ModuleInTestEnv. \
                   Please, put structs using Domo into compilation directories specific to your test environment \
                   and put paths to them in your mix.exs:

                   def project do
                     ...
                     elixirc_paths: elixirc_paths(Mix.env())
                     ...
                   end

                   defp elixirc_paths(:test), do: ["lib", "test/support"]
                   defp elixirc_paths(_), do: ["lib"]
                   """,
                   fn ->
                     defmodule ModuleInTestEnv do
                       use Domo

                       defstruct []
                       @type t :: %__MODULE__{}
                     end
                   end
    end

    test "raise CompileError when it's outside of the module scope" do
      assert_raise CompileError,
                   "nofile: use Domo should be called in a module scope only.",
                   fn ->
                     Code.compile_quoted(quote(do: use(Domo)))
                   end

      assert_raise CompileError,
                   "nofile: use Domo should be called in a module scope only.",
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

    test "raise the error for missing or unsupported t() for the struct" do
      message =
        Regex.compile!("""
        Type @type or @opaque t :: %__MODULE__{...} should be defined in the \
        #{inspect(__MODULE__)}.Module struct's module, that enables Domo \
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

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]

            @type t(a) :: a
          end
      end

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]

            @type t(kind) :: %Module{name: kind, title: String.t()}
            @type t :: t(integer())
          end
      end

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]

            @type t(kind) :: %Module{name: kind, title: String.t()}
          end
      end

      {:module, _, _bytecode, _} =
        defmodule Module1 do
          use Domo

          defstruct [:former]
          @type t :: %__MODULE__{former: integer}
        end

      assert_raise CompileError, message, fn ->
        {:module, _, _bytecode, _} =
          defmodule Module do
            use Domo

            @enforce_keys [:name, :title]
            defstruct [:name, :title]

            @type t(kind) :: %Module{name: kind, title: String.t()}
            @type t :: %Module1{}
          end
      end
    end

    test "Not raise when t() is defined alongside with other types" do
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

      module =
        defmodule ModuleOpaque do
          use Domo

          @enforce_keys [:name, :title]
          defstruct [:name, :title]

          @opaque name :: String.t()
          @opaque title :: String.t()
          @opaque t :: %__MODULE__{name: name(), title: title()}
        end

      assert {:module, _, _bytecode, _} = module
    end
  end

  describe "Domo after compile of the module should" do
    setup do
      allow ResolvePlanner.ensure_started(any(), any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any()), return: :ok
      allow ResolvePlanner.keep_module_environment(any(), any(), any()), return: :ok
      allow ResolvePlanner.plan_types_resolving(any(), any(), any(), any()), return: :ok
      allow ResolvePlanner.plan_empty_struct(any(), any()), return: :ok
      allow ResolvePlanner.plan_precond_checks(any(), any(), any()), return: :ok
      allow ResolvePlanner.plan_struct_defaults_ensurance(any(), any(), any(), any(), any()), return: :ok
      allow ResolvePlanner.plan_struct_integrity_ensurance(any(), any(), any(), any(), any()), return: :ok
      allow ResolvePlanner.flush(any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok

      :ok
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

    test "keep the module environment for further type resolve" do
      module_empty()

      expected_module = __MODULE__.Module

      assert_called ResolvePlanner.keep_module_environment(
                      any(),
                      expected_module,
                      is(fn env -> env.module == expected_module end)
                    )
    end

    test "plan resolvance of empty struct" do
      module_empty()

      expected_module = __MODULE__.Module

      assert_called ResolvePlanner.plan_empty_struct(any(), expected_module)
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

    test "plan struct defaults ensurance" do
      module_two_fields()

      call_line = 30

      assert_called ResolvePlanner.plan_struct_defaults_ensurance(
                      any(),
                      __MODULE__.Module,
                      [first: nil, second: 1.0],
                      is(fn file -> String.ends_with?(file, "/domo_use_test.exs") end),
                      call_line
                    )
    end

    test "plan struct integrity ensurance by calling new!" do
      module_custom_struct_as_default_value()

      call_line = 47

      assert_called ResolvePlanner.plan_struct_integrity_ensurance(
                      any(),
                      __MODULE__.Module.Submodule,
                      [title: "string"],
                      is(fn file -> String.ends_with?(file, "/domo_use_test.exs") end),
                      call_line
                    )

      expected_module = __MODULE__.Module

      assert %^expected_module{field: %{__struct__: __MODULE__.Module.Submodule, title: "string"}} = struct!(expected_module)
    end

    test "turn precond call into __precond__/1 function definition" do
      module_with_precond()

      map_10 = %{field: 1.0}
      assert true == apply(__MODULE__.Module, :__precond__, [:t, map_10])

      map_2 = %{field: 0.2}
      assert false == apply(__MODULE__.Module, :__precond__, [:t, map_2])

      assert true == apply(__MODULE__.Module, :__precond__, [:counter, 1])
      assert false == apply(__MODULE__.Module, :__precond__, [:counter, 0])
    end

    test "raise precond argument error if its not atom: function keyword" do
      message = """
      precond/1 expects [key: value] argument where the key is a type name \
      atom and the value is an anonymous boolean function with one argument \
      returning whether the precondition is fulfilled \
      for a value of the given type.\
      """

      assert_raise ArgumentError, message, fn ->
        defmodule Module do
          import Domo
          precond [{"field", "fun"}]
        end
      end

      assert_raise ArgumentError, message, fn ->
        defmodule Module do
          import Domo
          precond field: "fun"
        end
      end
    end

    test "raise error for precond call with undefined type" do
      message = """
      precond/1 is called with undefined :a_type type name. \
      The name of a type defined with @type attribute is expected.\
      """

      assert_raise ArgumentError, message, fn ->
        defmodule Module do
          import Domo
          precond a_type: fn _ -> true end
        end
      end

      assert_raise ArgumentError, message, fn ->
        defmodule Module do
          import Domo

          @type existing_type :: atom
          precond existing_type: fn _ -> true end
          precond a_type: fn _ -> true end
        end
      end
    end

    test "plan precond check for specified types in current module" do
      module_with_precond()

      expected_module = __MODULE__.Module

      expected_preconds = [
        t: "fn %{field: field} -> field > 0.5 end",
        value: "&Ext.value_valid?/1",
        counter: "&(&1 != 0)"
      ]

      assert_called ResolvePlanner.plan_precond_checks(any(), expected_module, expected_preconds)
    end
  end
end
