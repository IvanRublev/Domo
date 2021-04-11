defmodule Domo.TypeEnsurerFactory.ModuleInspectorTest do
  use Domo.FileCase

  alias Domo.TypeEnsurerFactory.ModuleInspector

  describe "ModuleInspector should" do
    test "detect module environment" do
      assert ModuleInspector.module_context?(%{module: Module, function: nil})
      refute ModuleInspector.module_context?(%{module: nil, function: nil})
      refute ModuleInspector.module_context?(%{module: Module, function: :function})
      refute ModuleInspector.module_context?(%{module: nil, function: :function})
    end

    test "load empty list when there are no types in a module" do
      assert {:ok, []} = ModuleInspector.beam_types(NoTypesModule)
    end

    test "load all types defined in a module" do
      assert {:ok,
              [
                opaque: {:op, {:type, _, :integer, []}, []},
                type:
                  {:sub_float,
                   {:remote_type, _,
                    [{:atom, _, ModuleNested.Module}, {:atom, _, :mod_float}, []]}, _},
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

    test "find type by name and return it in quoted form" do
      type_list = [type: {:t, {:type, 1, :atom, []}, []}]

      assert {:ok, quote(do: atom())} == ModuleInspector.find_type_quoted(:t, type_list)
    end

    test "find remote Elixir type by name and return it in the quoted form" do
      type_list = [
        type: {:rem_str, {:remote_type, 16, [{:atom, 0, String}, {:atom, 0, :t}, []]}, []}
      ]

      assert {:ok, {{:., [], [String, :t]}, [], []}} ==
               ModuleInspector.find_type_quoted(:rem_str, type_list)
    end

    test "find remote user type by name and return it in the quoted form" do
      type_list = [
        type:
          {:rem_int,
           {:remote_type, 39, [{:atom, 0, ModuleNested.Module.Submodule}, {:atom, 0, :op}, []]},
           []}
      ]

      assert {:ok, {{:., [], [ModuleNested.Module.Submodule, :op]}, [], []}} ==
               ModuleInspector.find_type_quoted(:rem_int, type_list)
    end

    test "find user type in the list recursively and return it in quoted form" do
      type_list = [
        {:typep, {:priv_atom, {:type, 16, :atom, []}, []}},
        {:type, {:ut, {:user_type, 17, :priv_atom, []}, ''}}
      ]

      assert {:ok, quote(do: atom())} == ModuleInspector.find_type_quoted(:ut, type_list)
    end
  end
end
