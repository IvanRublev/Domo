defmodule Domo.TypeEnsurerFactory.Resolver do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Resolver.Fields

  def resolve(plan_path, preconds_path, types_path, deps_path, write_file_module \\ File, verbose?) do
    with {:ok, plan} <- read_plan(plan_path),
         {:ok, plan} <- join_preconds(preconds_path, plan),
         {:ok, types, deps} <- resolve_plan(plan, plan_path, verbose?),
         :ok <- write_resolved_types(types, types_path, write_file_module),
         :ok <- append_modules_deps(deps, deps_path, write_file_module) do
      :ok
    else
      {:error, errors} ->
        {:error, errors |> List.wrap() |> Enum.map(&%Error{&1 | compiler_module: __MODULE__})}
    end
  end

  defp read_plan(plan_path) do
    case File.read(plan_path) do
      {:ok, binary} ->
        map = :erlang.binary_to_term(binary)

        {:ok,
         [
           fields: map.filed_types_to_resolve,
           envs: map.environments,
           anys_by_module: map.remote_types_as_any_by_module
         ]}

      _err ->
        {:error, %Error{file: plan_path, message: :no_plan}}
    end
  end

  defp join_preconds(preconds_path, plan) do
    case File.read(preconds_path) do
      {:ok, binary} ->
        map = :erlang.binary_to_term(binary)
        {:ok, Keyword.put(plan, :preconds, map)}

      _err ->
        {:error, %Error{file: preconds_path, message: :no_preconds}}
    end
  end

  def resolve_plan(plan, plan_path, verbose?) do
    fields = plan[:fields]
    preconds = plan[:preconds]
    envs = plan[:envs]

    if verbose? and map_size(plan[:anys_by_module]) > 0 do
      IO.write("""
      Domo treats the following remote types as any() by module:
      #{inspect(plan[:anys_by_module])}
      """)
    end

    case join_fields_envs(fields, envs) do
      {:ok, fields_envs} ->
        modules_count = map_size(fields)

        if modules_count > 0 do
          IO.puts("""
          Domo is compiling type ensurer for #{to_string(modules_count)} \
          module#{if modules_count > 1, do: "s"} (.ex)\
          """)
        end

        anys_by_module = plan[:anys_by_module]

        case resolve_plan_envs(fields_envs, preconds, anys_by_module, verbose?) do
          {module_filed_types, [], module_deps} ->
            updated_module_deps = add_type_hashes_to_dependant_modules(module_deps, preconds)
            {:ok, module_filed_types, updated_module_deps}

          {_module_filed_types, module_errors, _module_deps} ->
            {:error, wrap_module_errors(module_errors, envs)}
        end

      {:error, {:no_env_in_plan = error, module}} ->
        {:error, %Error{file: plan_path, struct_module: module, message: error}}
    end
  end

  defp join_fields_envs(plan, envs) do
    joined =
      Enum.reduce_while(plan, [], fn {module, fields}, list ->
        env = Map.get(envs, module)

        if is_nil(env) do
          {:halt, {:no_env_in_plan, module}}
        else
          {:cont, [{module, fields, env} | list]}
        end
      end)

    case joined do
      {:no_env_in_plan, _} = err -> {:error, err}
      joined -> {:ok, Enum.reverse(joined)}
    end
  end

  defp resolve_plan_envs(fields_envs, preconds, anys_by_module, verbose?) do
    resolvable_structs =
      fields_envs
      |> Enum.reduce([], fn {module, _fields, _env}, acc -> [module | acc] end)
      |> MapSet.new()

    Enum.reduce(fields_envs, {%{}, [], %{}}, fn {module, _fields, env} = mfe, {module_field_types, module_errors, module_deps} ->
      if verbose? do
        IO.puts("Resolve types of #{Alias.atom_to_string(module)}")
      end

      remote_types_as_any =
        Map.merge(
          anys_by_module[:global] || %{},
          anys_by_module[module] || %{},
          fn _key, type_names_lhs, type_names_rhs -> List.flatten([type_names_rhs | type_names_lhs]) end
        )

      {module, field_types, field_errors, type_deps} = Fields.resolve(mfe, preconds, remote_types_as_any, resolvable_structs)

      updated_module_field_types = Map.put(module_field_types, module, field_types)

      field_errors_by_module = join_module_if_nonempty(field_errors, module)
      updated_module_errors = field_errors_by_module ++ module_errors

      filtered_type_deps = reject_self_and_duplicates(module, type_deps)

      updated_module_deps =
        if Enum.empty?(filtered_type_deps) do
          module_deps
        else
          Map.put(module_deps, module, {env.file, filtered_type_deps})
        end

      {
        updated_module_field_types,
        updated_module_errors,
        updated_module_deps
      }
    end)
  end

  defp join_module_if_nonempty(field_errors, module) do
    if Enum.empty?(field_errors) do
      field_errors
    else
      Enum.map(field_errors, &{module, &1})
    end
  end

  defp reject_self_and_duplicates(module, deps) do
    deps
    |> Enum.reject(&(&1 == module))
    |> Enum.uniq()
  end

  defp add_type_hashes_to_dependant_modules(module_deps, preconds) do
    type_hash_by_module =
      module_deps
      |> Enum.reduce([], fn {module, {_path, dependant_modules}}, acc ->
        [module | dependant_modules] ++ acc
      end)
      |> Enum.uniq()
      |> Enum.map(&{&1, ModuleInspector.beam_types_hash(&1)})
      |> Enum.into(%{})

    preconds_hash_by_module =
      preconds
      |> Enum.reduce([], fn {module, types_precond_description}, list ->
        [{module, Fields.preconditions_hash(types_precond_description)} | list]
      end)
      |> Enum.into(%{})

    Enum.reduce(module_deps, %{}, fn {module, {path, dependants}}, map ->
      updated_dependants = Enum.map(dependants, &{&1, type_hash_by_module[&1], preconds_hash_by_module[&1]})
      Map.put(map, module, {path, updated_dependants})
    end)
  end

  defp wrap_module_errors(module_errors, envs) do
    Enum.map(module_errors, fn {module, error} ->
      message =
        case error do
          {:error, underlying_error} -> underlying_error
          other -> other
        end

      %Error{file: envs[module].file, struct_module: module, message: message}
    end)
  end

  defp write_resolved_types(map, types_path, file_module) do
    binary = :erlang.term_to_binary(map)

    case file_module.write(types_path, binary) do
      :ok -> :ok
      {:error, err} -> {:error, %Error{file: types_path, message: {:types_manifest_failed, err}}}
    end
  end

  defp append_modules_deps(deps_map, deps_path, file_module) do
    merged_map = merge_map_from_file(deps_path, deps_map, file_module)
    write_map(merged_map, deps_path, file_module)
  end

  defp merge_map_from_file(file, map, file_module) do
    case file_module.read(file) do
      {:ok, binary} -> Map.merge(:erlang.binary_to_term(binary), map)
      _ -> map
    end
  end

  defp write_map(map, file, file_module) do
    case file_module.write(file, :erlang.term_to_binary(map)) do
      :ok -> :ok
      {:error, err} -> {:error, %Error{file: file, message: {:deps_manifest_failed, err}}}
    end
  end
end
