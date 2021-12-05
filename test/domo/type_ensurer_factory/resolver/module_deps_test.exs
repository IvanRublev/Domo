defmodule Domo.TypeEnsurerFactory.Resolver.ModuleDepsTest do
  use Domo.FileCase
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Resolver
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias ModuleNested.Module.Submodule

  import ResolverTestHelper

  setup [:setup_project_planner]

  setup do
    allow CodeEvaluation.in_mix_compile?(any()), meck_options: [:passthrough], return: true
    :ok
  end

  defmodule FailingDepsFile do
    def write(path, _content) do
      if String.ends_with?(path, DomoMixTask.deps_manifest()) do
        {:error, :write_error}
      else
        :ok
      end
    end

    def read(_path), do: {:error, :noent}
  end

  describe "Resolver should" do
    test "write deps file and return :ok",
         %{
           planner: planner,
           plan_file: plan_file,
           preconds_file: preconds_file,
           types_file: types_file,
           deps_file: deps_file
         } do
      plan_types([quote(do: integer)], planner)

      assert :ok == Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)
      assert true == File.exists?(deps_file)
    end

    test "return error if can't write deps file", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(planner, quote(do: integer))
      keep_env(planner, __ENV__)
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: ^deps_file,
                  message: {:deps_manifest_failed, :write_error}
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, FailingDepsFile, false)
    end

    test "write resolved module => {its path, dependency modules with their type hashes and empty precondition descriptions hash} as value to a deps file",
         %{
           planner: planner,
           plan_file: plan_file,
           preconds_file: preconds_file,
           types_file: types_file,
           deps_file: deps_file
         } do
      plan(
        planner,
        LocalUserType,
        :remote_field_float,
        quote(context: ModuleNested, do: ModuleNested.mn_float())
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      expected_dependants = [{ModuleNested, ModuleInspector.beam_types_hash(ModuleNested), nil}]
      assert %{LocalUserType => {path, ^expected_dependants}} = read_deps(deps_file)
      assert path =~ "/user_types.ex"
    end

    test "write resolved module => {its path, dependency modules with their type hashes and precondition descriptions hash} as value to a deps file",
         %{
           planner: planner,
           plan_file: plan_file,
           preconds_file: preconds_file,
           types_file: types_file,
           deps_file: deps_file
         } do
      plan(
        planner,
        LocalUserType,
        :remote_field_float,
        quote(context: ModuleNested, do: ModuleNested.mn_float())
      )

      types_precond_description = [mn_float: "function body"]

      plan_precond_checks(
        planner,
        ModuleNested,
        types_precond_description
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      expected_dependants = [
        {
          ModuleNested,
          ModuleInspector.beam_types_hash(ModuleNested),
          preconds_hash(types_precond_description)
        }
      ]

      assert %{LocalUserType => {path, ^expected_dependants}} = read_deps(deps_file)
      assert path =~ "/user_types.ex"
    end

    test "write unique dependency modules rejecting duplicates", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(
        planner,
        LocalUserType,
        :remote_field_float,
        quote(context: ModuleNested, do: ModuleNested.mn_float())
      )

      plan(
        planner,
        LocalUserType,
        :some_other_field,
        quote(context: ModuleNested, do: ModuleNested.mn_float())
      )

      types_precond_description = [mn_float: "function body"]

      plan_precond_checks(
        planner,
        ModuleNested,
        types_precond_description
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      expected_dependants = [
        {
          ModuleNested,
          ModuleInspector.beam_types_hash(ModuleNested),
          preconds_hash(types_precond_description)
        }
      ]

      assert %{LocalUserType => {_path, ^expected_dependants}} = read_deps(deps_file)
    end

    test "Not write module itself as a dependency", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(
        planner,
        LocalUserType,
        :i,
        quote(context: LocalUserType, do: LocalUserType.int())
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      assert %{} == read_deps(deps_file)
    end

    test "write dependency modules for all planned field types", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(
        planner,
        LocalUserType,
        :remote_field_float,
        quote(context: ModuleNested, do: ModuleNested.mn_float())
      )

      plan(
        planner,
        LocalUserType,
        :some_atom,
        quote(context: Submodule, do: Submodule.t())
      )

      plan(
        planner,
        RemoteUserType,
        :some_int,
        quote(context: Submodule, do: Submodule.op())
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      keep_env(planner, RemoteUserType, RemoteUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      expected_local_dependants = [
        {ModuleNested, ModuleInspector.beam_types_hash(ModuleNested), nil},
        {Submodule, ModuleInspector.beam_types_hash(Submodule), nil}
      ]

      expected_remote_dependants = [
        {Submodule, ModuleInspector.beam_types_hash(Submodule), nil}
      ]

      assert %{
               LocalUserType => {local_source_path, ^expected_local_dependants},
               RemoteUserType => {remote_source_path, ^expected_remote_dependants}
             } = read_deps(deps_file)

      assert local_source_path == remote_source_path
      assert remote_source_path =~ "/user_types.ex"
    end

    test "overwrite deps for a planned module keeping previously resolved module's deps intact",
         %{
           planner: planner,
           plan_file: plan_file,
           preconds_file: preconds_file,
           types_file: types_file,
           deps_file: deps_file
         } do
      nested_dependant = [{ModuleNested, ModuleInspector.beam_types_hash(ModuleNested), preconds_hash(mn_float: "function body 1")}]
      some_module_dependant = [{SomeModule, ModuleInspector.beam_types_hash(SomeModule), nil}]

      previous_deps = [
        {Submodule, ModuleInspector.beam_types_hash(Submodule)},
        {SomeModule, ModuleInspector.beam_types_hash(SomeModule)}
      ]

      File.write!(
        deps_file,
        :erlang.term_to_binary(%{
          ModuleStoredBefore => {".../module_stored_before.ex", nested_dependant},
          AffectedModule => {".../affected_module.ex", some_module_dependant},
          LocalUserType => {".../previous_local_user.ex", previous_deps}
        })
      )

      plan(
        planner,
        LocalUserType,
        :remote_field_float,
        quote(context: ModuleNested, do: ModuleNested.mn_float())
      )

      plan_precond_checks(
        planner,
        ModuleNested,
        mn_float: "function body 1"
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      assert %{
               ModuleStoredBefore => {".../module_stored_before.ex", ^nested_dependant},
               AffectedModule => {".../affected_module.ex", ^some_module_dependant},
               LocalUserType => {local_source_path, ^nested_dependant}
             } = read_deps(deps_file)

      assert local_source_path =~ "/user_types.ex"
    end

    test "write every intermediate dependency", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(
        planner,
        LocalUserType,
        :remote_field_sub_float,
        quote(context: RemoteUserType, do: RemoteUserType.sub_float())
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      expected_dependants = [
        {ModuleNested, ModuleInspector.beam_types_hash(ModuleNested), nil},
        {ModuleNested.Module, ModuleInspector.beam_types_hash(ModuleNested.Module), nil},
        {ModuleNested.Module.Submodule, ModuleInspector.beam_types_hash(ModuleNested.Module.Submodule), nil},
        {RemoteUserType, ModuleInspector.beam_types_hash(RemoteUserType), nil}
      ]

      assert %{LocalUserType => {path, ^expected_dependants}} = read_deps(deps_file)
      assert path =~ "/user_types.ex"
    end
  end
end
