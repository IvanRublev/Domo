defmodule DomoInMemoryTest do
  use Domo.FileCase, async: false
  use Placebo

  import ExUnit.CaptureIO

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Resolver

  setup do
    Code.compiler_options(ignore_module_conflict: true)

    ResolverTestHelper.disable_raise_in_test_env()
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: false

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
      ResolverTestHelper.stop_in_memory_planner()
      ResolverTestHelper.enable_raise_in_test_env()
    end)

    :ok
  end

  describe "To build in memory TypeEnsurer the Domo should" do
    setup do
      allow ModuleInspector.ensure_loaded?(any()), meck_options: [:passthrough], return: true
      allow ModuleInspector.has_type_ensurer?(any()), meck_options: [:passthrough], return: false

      allow Resolver.resolve_plan(any(), any(), any()), meck_options: [:passthrough], exec: &:meck.passthrough([&1, &2, &3])
      allow Generator.generate_one(any(), any()), meck_options: [:passthrough], exec: &:meck.passthrough([&1, &2])

      :ok
    end

    test "resolve types of module having local types only" do
      defmodule ModuleLocal do
        use Domo, ensure_struct_defaults: false
        defstruct [:id]

        @type id :: String.t()
        @type t :: %__MODULE__{id: id()}
        precond t: &(String.length(&1.id) < 5)
      end

      assert_called Resolver.resolve_plan(any(), :in_memory, false)
      assert_called Generator.generate_one(any(), any())

      assert %{__struct__: ModuleLocal, id: "1001"} = ModuleLocal.new!(id: "1001")
      assert {:error, _message} = ModuleLocal.new(id: 100)
      assert {:error, _message} = ModuleLocal.new(id: "1001500")
    end

    test "resolve types of module referencing remote type in BEAM on disk" do
      defmodule ModuleLocal do
        use Domo, ensure_struct_defaults: false
        defstruct [:id]

        @type t :: %__MODULE__{id: ModuleNested.mn_float()}
      end

      assert %{__struct__: ModuleLocal, id: 1.0} = ModuleLocal.new!(id: 1.0)
      assert {:error, _message} = ModuleLocal.new(id: 100)
    end

    test "resolve types of module referencing remote type of in memory module" do
      defmodule ModuleMemoryTypes do
        use Domo.InteractiveTypesRegistration

        @type id :: integer()
      end

      defmodule ModuleLocal do
        use Domo, ensure_struct_defaults: false
        defstruct [:id]

        @type t :: %__MODULE__{id: ModuleMemoryTypes.id()}
      end

      assert %{__struct__: ModuleLocal, id: 100} = ModuleLocal.new!(id: 100)
      assert {:error, _message} = ModuleLocal.new(id: 1.00)
    end

    test "validates struct's defaults" do
      assert_raise CompileError, ~r(A default value given via defstruct/1 in .* module mismatches the type.), fn ->
        defmodule ModuleLocal do
          use Domo
          defstruct id: "not an integer", name: :none

          @type t :: %__MODULE__{id: integer(), name: String.t()}
        end
      end
    end

    test "ensures remote types as any type listing them in `remote_types_as_any` option or in project config" do
      :meck.unload(ModuleInspector)

      defmodule ModuleLocal do
        alias The.Nested.EmptyStruct

        use Domo, remote_types_as_any: [{EmptyStruct, :t}, {CustomStructUsingDomo, [:t]}], ensure_struct_defaults: false

        defstruct [:placeholder, :custom_struct]

        @type t :: %__MODULE__{
                placeholder: The.Nested.EmptyStruct.t(),
                custom_struct: CustomStructUsingDomo.t()
              }
      end

      assert {:ok, _} = ModuleLocal.new(placeholder: nil, custom_struct: 1)

      Application.put_env(:domo, :remote_types_as_any, [{The.Nested.EmptyStruct, :t}])

      defmodule ModuleLocalMixed do
        use Domo, remote_types_as_any: [{CustomStructUsingDomo, [:t]}], ensure_struct_defaults: false

        defstruct [:placeholder, :custom_struct]

        @type t :: %__MODULE__{
                placeholder: The.Nested.EmptyStruct.t(),
                custom_struct: CustomStructUsingDomo.t()
              }
      end

      assert {:ok, _} = ModuleLocalMixed.new(placeholder: nil, custom_struct: 1)
    after
      Application.delete_env(:domo, :remote_types_as_any)
    end

    test "ensure Ecto.Schema.Metadata.t() type as any coming as default behaviour" do
      defmodule SchemaHolder do
        use Domo, ensure_struct_defaults: false

        defstruct [:schema]

        @type t :: %__MODULE__{schema: Ecto.Schema.Metadata.t()}
      end

      assert {:ok, _} = SchemaHolder.new(schema: :none)
    end

    test "raises error if can't resolve type of in memory module (not defined yet)" do
      assert_raise RuntimeError,
                   """
                   Can't resolve NotDefinedModule.id() type. Please, define the module first or \
                   use Domo.InteractiveTypesRegistration in it to inform Domo about the types.\
                   """,
                   fn ->
                     defmodule ModuleLocal do
                       use Domo
                       defstruct [:id]

                       @type t :: %__MODULE__{id: NotDefinedModule.id()}
                     end
                   end
    end

    test "print warning redefining dependency module in memory" do
      alias __MODULE__.{ModuleMemoryTypes, ChildMemoryStruct}

      warning =
        capture_io(:stderr, fn ->
          defmodule ModuleMemoryTypes do
            use Domo.InteractiveTypesRegistration

            @type id :: integer()
          end
        end)

      assert warning == ""

      warning =
        capture_io(:stderr, fn ->
          defmodule ChildMemoryStruct do
            use Domo, ensure_struct_defaults: false

            defstruct [:id]
            @type t :: %__MODULE__{id: id()}
            @type id :: integer()
          end
        end)

      assert warning == ""

      defmodule ModuleLocal do
        use Domo, ensure_struct_defaults: false
        defstruct [:id, :child_id]

        @type t :: %__MODULE__{id: ModuleMemoryTypes.id(), child_id: ChildMemoryStruct.id()}
      end

      warning =
        capture_io(:stderr, fn ->
          defmodule ModuleMemoryTypes do
            use Domo.InteractiveTypesRegistration

            @type id :: atom()
          end
        end)

      assert warning =~ """
             TypeEnsurer modules are invalidated. Please, redefine the following modules \
             depending on #{inspect(ModuleMemoryTypes)} to make their types \
             ensurable again: #{inspect(ModuleLocal)}\
             """

      warning =
        capture_io(:stderr, fn ->
          defmodule ChildMemoryStruct do
            use Domo, ensure_struct_defaults: false

            defstruct [:id]
            @type t :: %__MODULE__{id: id()}
            @type id :: atom()
          end
        end)

      assert warning =~ """
             TypeEnsurer modules are invalidated. Please, redefine the following modules \
             depending on #{inspect(ChildMemoryStruct)} to make their types \
             ensurable again: #{inspect(ModuleLocal)}\
             """
    end

    test "invalidate type ensurers of depending module reregistering dependency module types in memory" do
      defmodule ModuleMemoryTypes do
        use Domo.InteractiveTypesRegistration

        @type id :: integer()
      end

      defmodule ModuleLocal do
        use Domo, ensure_struct_defaults: false
        defstruct [:id]

        @type t :: %__MODULE__{id: ModuleMemoryTypes.id()}
      end

      assert {:ok, _} = ModuleLocal.new(id: 125)

      defmodule ModuleMemoryTypes do
        use Domo.InteractiveTypesRegistration

        @type id :: atom()
      end

      assert_raise RuntimeError,
                   """
                   TypeEnsurer module is invalid. Please, redefine #{inspect(ModuleLocal)} \
                   to make constructor, validation, and reflection functions to work again.\
                   """,
                   fn ->
                     ModuleLocal.new(id: 125)
                   end
    end

    test "invalidate type ensurers of depending module redefining dependency struct in memory" do
      defmodule ChildMemoryStruct do
        use Domo, ensure_struct_defaults: false

        defstruct [:id]
        @type t :: %__MODULE__{id: id()}
        @type id :: integer()
      end

      defmodule ModuleLocal do
        use Domo, ensure_struct_defaults: false
        defstruct [:id]

        @type t :: %__MODULE__{id: ChildMemoryStruct.id()}
      end

      assert {:ok, _} = ModuleLocal.new(id: 125)

      defmodule ChildMemoryStruct do
        use Domo, ensure_struct_defaults: false

        defstruct [:id]
        @type t :: %__MODULE__{id: id()}
        @type id :: atom()
      end

      assert_raise RuntimeError,
                   """
                   TypeEnsurer module is invalid. Please, redefine #{inspect(ModuleLocal)} \
                   to make constructor, validation, and reflection functions to work again.\
                   """,
                   fn ->
                     ModuleLocal.new(id: 125)
                   end
    end
  end

  describe "Domo having :domo :verbose_in_iex option set to true should" do
    test "print verbose messages registering module types" do
      Application.put_env(:domo, :verbose_in_iex, true)

      msg =
        capture_io(fn ->
          defmodule ModuleMemoryTypes do
            use Domo.InteractiveTypesRegistration

            @type id :: integer()
          end
        end)

      assert msg =~ "Domo resolve planner started"
    after
      Application.delete_env(:domo, :verbose_in_iex)
    end

    test "print verbose messages defining a struct" do
      Application.put_env(:domo, :verbose_in_iex, true)

      msg =
        capture_io(fn ->
          defmodule ModuleLocal do
            use Domo, ensure_struct_defaults: false
            defstruct [:id]

            @type t :: %__MODULE__{id: integer()}
          end
        end)

      assert msg =~ "Domo resolve planner started"
      assert msg =~ "Resolve types of DomoInMemoryTest.ModuleLocal"
      assert msg =~ "Domo generates TypeEnsurer modules source code and load them into memory."
    after
      Application.delete_env(:domo, :verbose_in_iex)
    end
  end
end
