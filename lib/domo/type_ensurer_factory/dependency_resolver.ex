defmodule Domo.TypeEnsurerFactory.DependencyResolver do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Error
  alias Kernel.ParallelCompiler

  def maybe_recompile_depending_structs(deps_path, file_module \\ File) do
    with {:ok, content} <- read_deps(deps_path, file_module),
         {:ok, deps} <- decode_deps(content),
         type_hash_by_dependant_module = get_dependant_module_hashes(deps),
         {:ok, updated_deps} <-
           maybe_rewrite_deps(
             deps_path,
             deps,
             type_hash_by_dependant_module,
             file_module
           ) do
      maybe_recompile(updated_deps, deps, type_hash_by_dependant_module)
    else
      {:error, {:read_deps, :enoent}} ->
        {:ok, [], []}

      {:error, {_operation, _message} = error} ->
        %Error{
          compiler_module: __MODULE__,
          file: deps_path,
          struct_module: nil,
          message: error
        }
    end
  end

  defp read_deps(deps_path, file_module) do
    case file_module.read(deps_path) do
      {:ok, _content} = ok -> ok
      {:error, message} -> {:error, {:read_deps, message}}
    end
  end

  defp decode_deps(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _error -> {:error, {:decode_deps, :malformed_binary}}
    end
  end

  defp get_dependant_module_hashes(deps) do
    deps
    |> Map.values()
    |> Enum.flat_map(fn {_path, module_type_hash_list} -> module_type_hash_list end)
    |> Enum.uniq()
    |> Enum.map(fn {module, _type_old_hash} ->
      {module, ModuleInspector.beam_types_hash(module)}
    end)
    |> Enum.into(%{})
  end

  defp maybe_rewrite_deps(deps_path, deps, type_hash_by_dependant_module, file_module) do
    updated_deps = remove_modules_with_unloadable_types(deps, type_hash_by_dependant_module)

    if updated_deps == deps do
      {:ok, updated_deps}
    else
      case file_module.write(deps_path, :erlang.term_to_binary(updated_deps)) do
        :ok -> {:ok, updated_deps}
        {:error, message} -> {:error, {:update_deps, message}}
      end
    end
  end

  defp remove_modules_with_unloadable_types(deps, type_hash_by_dependant_module) do
    Enum.reduce(deps, %{}, fn {module, {path, dependants}}, acc ->
      if ModuleInspector.beam_types_hash(module) == nil do
        acc
      else
        updated_dependants =
          remove_dependant_modules_with_unloadable_types(
            dependants,
            type_hash_by_dependant_module
          )

        Map.put(acc, module, {path, updated_dependants})
      end
    end)
  end

  defp remove_dependant_modules_with_unloadable_types(dependants, type_hashes_by_module) do
    dependants
    |> Enum.reduce([], fn {dependant_module, _original_hash} = dependant, acc ->
      if type_hashes_by_module[dependant_module] == nil do
        acc
      else
        [dependant | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp maybe_recompile(updated_deps, deps, type_hash_by_dependant_module) do
    sources_to_recompile =
      updated_deps
      |> sources_with_changed_dependants_type_hash(type_hash_by_dependant_module)
      |> add_sources_for_modules_of_changed_dependants(updated_deps, deps)
      |> add_sources_dependind_on_changed_sources(deps)
      |> Map.values()
      |> Enum.uniq()

    if Enum.empty?(sources_to_recompile) do
      {:ok, [], []}
    else
      touch_and_recompile(sources_to_recompile)
    end
  end

  defp sources_with_changed_dependants_type_hash(deps, dependant_module_type_hashes) do
    Enum.reduce(deps, %{}, fn {module, {path, dependants}}, acc ->
      if any_type_hash_changed?(dependants, dependant_module_type_hashes) do
        Map.put(acc, module, path)
      else
        acc
      end
    end)
  end

  defp any_type_hash_changed?(dependants, dependant_module_type_hashes) do
    Enum.any?(dependants, fn {module, old_hash} ->
      new_hash = dependant_module_type_hashes[module]
      old_hash != new_hash
    end)
  end

  defp add_sources_for_modules_of_changed_dependants(sources_by_module, updated_deps, deps) do
    changed_sources =
      Enum.reduce(updated_deps, %{}, fn {module, {path, dependants}}, acc ->
        {_path, original_dependants} = deps[module]

        if original_dependants != dependants do
          Map.put(acc, module, path)
        else
          acc
        end
      end)

    Map.merge(sources_by_module, changed_sources)
  end

  defp add_sources_dependind_on_changed_sources(source_by_module_to_recompile, deps) do
    updated_map = do_add_sources_dependind_on_changed_sources(source_by_module_to_recompile, deps)

    if updated_map != source_by_module_to_recompile do
      add_sources_dependind_on_changed_sources(updated_map, deps)
    else
      updated_map
    end
  end

  defp do_add_sources_dependind_on_changed_sources(source_by_module_to_recompile, deps) do
    Enum.reduce(deps, source_by_module_to_recompile, fn
      {module, {source_path, dependants}}, acc ->
        Enum.reduce(dependants, acc, fn {dependant_module, _hash}, acc ->
          maybe_add_moudle_path(acc, module, source_path, dependant_module)
        end)
    end)
  end

  defp maybe_add_moudle_path(acc, module, source_path, dependant_module) do
    if Map.has_key?(acc, dependant_module) do
      Map.put(acc, module, source_path)
    else
      acc
    end
  end

  defp touch_and_recompile(sources_to_recompile) do
    touch_files(sources_to_recompile)

    project = Mix.Project.config()
    dest = Mix.Project.compile_path(project)

    ParallelCompiler.compile_to_path(sources_to_recompile, dest)
  end

  defp touch_files(paths_list) do
    Enum.map(paths_list, fn path ->
      File.touch!(path)
      path
    end)
  end
end
