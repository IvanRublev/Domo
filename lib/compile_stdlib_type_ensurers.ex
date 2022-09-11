alias Domo.TypeEnsurerFactory

# We wait for compilation of MatchFunRegistry submodules explicitly to prevent function not found crash.
parent_module = Domo.TypeEnsurerFactory.Generator.MatchFunRegistry
cwd = File.cwd!()
modules_path = Path.relative_to(Path.join("lib", Macro.underscore(parent_module)), cwd)
extension = ".ex"

wait_for_list =
  "#{modules_path}/**/*#{extension}"
  |> Path.wildcard()
  |> Enum.map(&(&1 |> Path.basename() |> String.replace_suffix(extension, "") |> Macro.camelize()))
  |> Enum.map(&Module.concat(parent_module, &1))

Enum.each(wait_for_list, &Code.ensure_compiled/1)

verbose? = false

TypeEnsurerFactory.start_resolve_planner(:in_memory, :in_memory, verbose?: verbose?)
TypeEnsurerFactory.maybe_collect_types_for_stdlib_structs(:in_memory)
{:ok, plan, preconds} = TypeEnsurerFactory.get_plan_state(:in_memory)
{:ok, module_filed_types, _dependencies_by_module, _ecto_assocs_by_module} = TypeEnsurerFactory.resolve_plan(plan, preconds, verbose?)
TypeEnsurerFactory.strop_resolve_planner(:in_memory)

types_path = Path.join(Mix.Project.manifest_path(), "resolved_stdlib_types.domo")
ecto_assocs_path = Path.join(Mix.Project.manifest_path(), "resolved_stdlib_ecto_assocs.domo")
code_path = Path.join(Mix.Project.manifest_path(), "/domo_generated_stdlib_ensurers_code")

binary = :erlang.term_to_binary(module_filed_types)
File.write!(types_path, binary)
# There is no dependency from standard lib modules on Ecto, so we can't have schemas and assoc fields.
binary = :erlang.term_to_binary(%{})
File.write!(ecto_assocs_path, binary)

{:ok, type_ensurer_paths} = TypeEnsurerFactory.generate_type_ensurers(types_path, ecto_assocs_path, code_path, verbose?)
{:ok, {_modules, ens_warns}} = TypeEnsurerFactory.compile_type_ensurers(type_ensurer_paths, verbose?)

unless Enum.empty?(ens_warns) do
  IO.puts(inspect(ens_warns))
end

File.rm_rf!(types_path)
File.rm_rf!(code_path)
