defmodule Domo.TypeEnsurerFactory.Resolver do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Resolver.Fields

  @spec resolve(String.t(), String.t(), String.t(), module) :: :ok | {:error, [Error.t()]}
  def resolve(plan_path, types_path, deps_path, write_file_module \\ File) do
    with {:ok, {plan, envs}} <- read_plan(plan_path),
         {:ok, types, deps} <- resolve_plan(plan, envs, plan_path),
         :ok <- write_resolved_types(types, types_path, write_file_module),
         :ok <- append_modules_deps(deps, deps_path, write_file_module) do
      :ok
    else
      {:error, errors} ->
        {:error, errors |> List.wrap() |> Enum.map(&%Error{&1 | compiler_module: __MODULE__})}
    end
  end

  @spec read_plan(String.t()) :: {:ok, {map, list}} | {:error, map}
  defp read_plan(plan_path) do
    case File.read(plan_path) do
      {:ok, binary} ->
        map_list = :erlang.binary_to_term(binary)
        {:ok, map_list}

      _err ->
        {:error, %Error{file: plan_path, message: :no_plan}}
    end
  end

  @spec resolve_plan(map, map, String.t()) :: {:ok, map, map} | {:error, map}
  defp resolve_plan(plan, envs, plan_path) do
    case join_plan_envs(plan, envs) do
      {:ok, plan_envs} ->
        modules_count = length(plan_envs)

        IO.puts("""
        Domo is compiling type ensurer for #{to_string(modules_count)} \
        module#{if modules_count > 1, do: "s"} (.ex)\
        """)

        case resolve_plan_envs(plan_envs) do
          {module_filed_types, [], module_deps} ->
            {:ok, module_filed_types, module_deps}

          {_module_filed_types, module_errors, _module_deps} ->
            {:error, wrap_module_errors(module_errors, envs)}
        end

      {:error, {:no_env_in_plan = error, module}} ->
        {:error, %Error{file: plan_path, struct_module: module, message: error}}
    end
  end

  @spec join_plan_envs(map, map) :: {:ok, map} | {:error, tuple}
  defp join_plan_envs(plan, envs) do
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

  @spec resolve_plan_envs(map) :: {map, [{module, :error, any()}], map}
  defp resolve_plan_envs(plan_envs) do
    Enum.reduce(plan_envs, {%{}, [], %{}}, fn {module, fields, env},
                                              {module_field_types, module_errors, module_deps} ->
      {module, field_types, field_errors, deps} = Fields.resolve(module, fields, env)

      updated_module_field_types = Map.put(module_field_types, module, field_types)

      field_errors_by_module = join_module_if_nonempty(field_errors, module)
      updated_module_errors = field_errors_by_module ++ module_errors

      filtered_deps = reject_self_and_duplicates(module, deps)

      updated_module_deps =
        if Enum.empty?(filtered_deps) do
          module_deps
        else
          Map.put(module_deps, module, {env.file, filtered_deps})
        end

      {
        updated_module_field_types,
        updated_module_errors,
        updated_module_deps
      }
    end)
  end

  defp reject_self_and_duplicates(module, deps) do
    deps
    |> Enum.reject(&(&1 == module))
    |> Enum.uniq()
  end

  defp join_module_if_nonempty(field_errors, module) do
    if Enum.empty?(field_errors) do
      field_errors
    else
      Enum.map(field_errors, &{module, &1})
    end
  end

  @spec wrap_module_errors(map, map) :: [Error.t()] | []
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

  @spec write_resolved_types(map, String.t(), module) :: :ok | {:error, map}
  defp write_resolved_types(map, types_path, file_module) do
    binary = :erlang.term_to_binary(map)

    case file_module.write(types_path, binary) do
      :ok -> :ok
      {:error, err} -> {:error, %Error{file: types_path, message: {:types_manifest_failed, err}}}
    end
  end

  @spec append_modules_deps(map, String.t(), module) :: :ok | {:error, map}
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
