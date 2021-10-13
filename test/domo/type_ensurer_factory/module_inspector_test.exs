defmodule Domo.TypeEnsurerFactory.ModuleInspectorTest do
  use Domo.FileCase

  alias Domo.TypeEnsurerFactory.ModuleInspector

  test "ModuleInspector detects module environment" do
    assert ModuleInspector.module_context?(%{module: Module, function: nil})
    refute ModuleInspector.module_context?(%{module: nil, function: nil})
    refute ModuleInspector.module_context?(%{module: Module, function: :function})
    refute ModuleInspector.module_context?(%{module: nil, function: :function})
  end

  test "ModuleInspector returns type ensurer module name for the given module" do
    assert ModuleInspector.type_ensurer(Module) == Module.TypeEnsurer
  end

  test "ModuleInspector returns whether the given module has type ensurer" do
    assert ModuleInspector.has_type_ensurer?(CustomStructUsingDomo) == true
    assert ModuleInspector.has_type_ensurer?(CustomStruct) == false
  end

  describe "ModuleInspector for types should" do
    test "load empty list when there are no types in a module" do
      assert {:ok, []} = ModuleInspector.beam_types(NoTypesModule)
    end

    test "load all types defined in a module" do
      assert {:ok,
              [
                opaque: {:op, {:type, _, :integer, []}, []},
                type: {:sub_float, {:remote_type, _, [{:atom, _, ModuleNested.Module}, {:atom, _, :mod_float}, []]}, _},
                type: {:t, {:type, _, :atom, []}, []}
              ]} = ModuleInspector.beam_types(ModuleNested.Module.Submodule)
    end

    test "return no_beam_file error if no beam file can be found for module or no types can be loaded" do
      assert {:error, {:no_beam_file, ModuleNested.Module.Submodule}} ==
               ModuleInspector.beam_types(
                 ModuleNested.Module.Submodule,
                 fn _module -> {:error, :badfile} end
               )

      assert {:error, {:no_beam_file, ModuleNested.Module.Submodule}} ==
               ModuleInspector.beam_types(
                 ModuleNested.Module.Submodule,
                 fn module -> {:module, module} end,
                 fn _module -> :error end
               )
    end

    test "return type_not_found error when can't find type in list" do
      assert {:error, {:type_not_found, :t}} == ModuleInspector.find_type_quoted(:t, [])
    end

    test "return parametrized_type_not_supported giving parametrized type to find" do
      type_list = [
        type: {:t, {:user_type, 50, :t, [{:type, 50, :module, []}]}, []},
        type: {:context, {:type, 40, :any, []}, []},
        type: {:state, {:type, 38, :union, [{:atom, 0, :built}, {:atom, 0, :loaded}, {:atom, 0, :deleted}]}, []}
      ]

      assert {:error, {:parametrized_type_not_supported, :t}} == ModuleInspector.find_type_quoted(:t, type_list)
    end

    test "return hash of module types giving loadable module" do
      assert <<165, 63, 215, 58, 173, 14, 220, 157, 192, 81, 20, 19, 68, 90, 147, 171>> ==
               ModuleInspector.beam_types_hash(EmptyStruct)
    end

    test "return nil as hash of module types giving unloadable module" do
      assert nil == ModuleInspector.beam_types_hash(NonexistingModule)
    end

    test "find type by name and return it in quoted form" do
      type_list = [type: {:t, {:type, 1, :atom, []}, []}]

      assert {:ok, quote(do: atom()), []} == ModuleInspector.find_type_quoted(:t, type_list)
    end

    test "find remote Elixir type by name and return it in the quoted form" do
      type_list = [
        type: {:rem_str, {:remote_type, 16, [{:atom, 0, String}, {:atom, 0, :t}, []]}, []}
      ]

      assert {:ok, {{:., [], [String, :t]}, [], []}, []} ==
               ModuleInspector.find_type_quoted(:rem_str, type_list)
    end

    test "find remote Elixir type referenced by private local type and return it in the quoted form" do
      type_list = [
        typep: {:rem_str, {:remote_type, 16, [{:atom, 0, String}, {:atom, 0, :t}, []]}, []},
        type: {:ut, {:user_type, 17, :rem_str, []}, ''}
      ]

      assert {:ok, {{:., [], [String, :t]}, [], []}, [:rem_str]} ==
               ModuleInspector.find_type_quoted(:ut, type_list)
    end

    test "find remote user type by name and return it in the quoted form" do
      type_list = [
        type: {:rem_int, {:remote_type, 39, [{:atom, 0, ModuleNested.Module.Submodule}, {:atom, 0, :op}, []]}, []}
      ]

      assert {:ok, {{:., [], [ModuleNested.Module.Submodule, :op]}, [], []}, []} ==
               ModuleInspector.find_type_quoted(:rem_int, type_list)
    end

    test "find local user type in the list recursively and return it in quoted form" do
      type_list = [
        {:typep, {:priv_atom, {:type, 16, :atom, []}, []}},
        {:type, {:ut, {:user_type, 17, :priv_atom, []}, ''}}
      ]

      assert {:ok, quote(do: atom()), [:priv_atom]} == ModuleInspector.find_type_quoted(:ut, type_list)
    end

    test "find local user type for integer or atom and return it in quoted form" do
      type_list = [
        {:type, {:atom_hello, {:atom, 0, :hello}, []}},
        {:type, {:number_one, {:integer, 0, 1}, []}}
      ]

      assert {:ok, :hello, []} == ModuleInspector.find_type_quoted(:atom_hello, type_list)
      assert {:ok, 1, []} == ModuleInspector.find_type_quoted(:number_one, type_list)
    end
  end
end
