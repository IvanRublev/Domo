defmodule Domo.TypeEnsurerFactory.DependencyResolver do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.DependencyResolver.ElixirTask
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Resolver.Fields

  def maybe_recompile_depending_structs(deps_path, preconds_path, opts) do
    file_module = opts[:file_module] || File

    with {:ok, content} <- read_deps(deps_path, file_module),
         {:ok, deps} <- decode_deps(content),
         {:ok, content} <- read_preconds(preconds_path, file_module),
         {:ok, preconds} <- decode_preconds(content),
         {:ok, updated_deps, type_hash_by_dependant_module} <- maybe_cleanup_and_write_deps(deps_path, deps, file_module),
         {:ok, updated_preconds} <- maybe_cleanup_preconds(preconds_path, preconds, file_module) do
      preconds_hash_by_module = get_precond_hashes(updated_preconds)
      maybe_recompile(updated_deps, deps, type_hash_by_dependant_module, preconds_hash_by_module, opts[:verbose?] || false)
    else
      {:error, {:read_deps, :enoent}} ->
        {:ok, []}

      {:error, {operation, _message} = error} when operation in [:read_deps, :decode_deps, :update_deps] ->
        %Error{
          compiler_module: __MODULE__,
          file: deps_path,
          struct_module: nil,
          message: error
        }

      {:error, {operation, _message} = error} when operation in [:read_preconds, :decode_preconds, :update_preconds] ->
        %Error{
          compiler_module: __MODULE__,
          file: preconds_path,
          struct_module: nil,
          message: error
        }

      {:error, [_ | _]} = error ->
        error
    end
  end

  defp read_deps(deps_path, file_module) do
    case file_module.read(deps_path) do
      {:ok, _content} = ok -> ok
      {:error, message} -> {:error, {:read_deps, message}}
    end
  end

  defp read_preconds(preconds_path, file_module) do
    case file_module.read(preconds_path) do
      {:ok, _content} = ok -> ok
      {:error, message} -> {:error, {:read_preconds, message}}
    end
  end

  defp decode_deps(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _error -> {:error, {:decode_deps, :malformed_binary}}
    end
  end

  defp decode_preconds(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _error -> {:error, {:decode_preconds, :malformed_binary}}
    end
  end

  defp get_dependant_module_hashes(deps) do
    deps
    |> Map.values()
    |> Enum.flat_map(fn {_path, module_type_hash_list} -> module_type_hash_list end)
    |> Enum.uniq()
    |> Enum.map(fn {module, _type_old_hash, _precond_old_hash} ->
      {module, ModuleInspector.beam_types_hash(module)}
    end)
    |> Enum.into(%{})
  end

  defp get_precond_hashes(preconds) do
    preconds
    |> Enum.map(fn {module, types_precond_description} ->
      {module, Fields.preconditions_hash(types_precond_description)}
    end)
    |> Enum.into(%{})
  end

  defp maybe_cleanup_and_write_deps(deps_path, deps, file_module) do
    loadable_deps = remove_unloadable_modules(deps)
    type_hash_by_dependant_module = get_dependant_module_hashes(loadable_deps)
    updated_deps = remove_modules_with_unloadable_types(loadable_deps, type_hash_by_dependant_module)

    if updated_deps == deps do
      {:ok, updated_deps, type_hash_by_dependant_module}
    else
      case file_module.write(deps_path, :erlang.term_to_binary(updated_deps)) do
        :ok -> {:ok, updated_deps, type_hash_by_dependant_module}
        {:error, message} -> {:error, {:update_deps, message}}
      end
    end
  end

  defp maybe_cleanup_preconds(preconds_path, preconds, file_module) do
    updated_preconds =
      Enum.reduce(preconds, %{}, fn {module, type_precond_description}, map ->
        if Code.ensure_loaded?(module) and Kernel.function_exported?(module, :__precond__, 2) do
          Map.put(map, module, type_precond_description)
        else
          map
        end
      end)

    if map_size(updated_preconds) != map_size(preconds) do
      case file_module.write(preconds_path, :erlang.term_to_binary(updated_preconds)) do
        :ok -> {:ok, updated_preconds}
        {:error, message} -> {:error, {:update_preconds, message}}
      end
    else
      {:ok, preconds}
    end
  end

  defp remove_unloadable_modules(deps) do
    Enum.reduce(deps, %{}, fn {module, {path, dependants}}, acc ->
      if Code.ensure_loaded?(module) do
        updated_dependants = remove_unloadable_dependant_modules(dependants)
        Map.put(acc, module, {path, updated_dependants})
      else
        acc
      end
    end)
  end

  defp remove_unloadable_dependant_modules(dependants) do
    Enum.filter(dependants, fn {dependant_module, _type_old_hash, _precond_old_hash} ->
      Code.ensure_loaded?(dependant_module)
    end)
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
    |> Enum.reduce([], fn {dependant_module, _type_old_hash, _precond_old_hash} = dependent, acc ->
      if type_hashes_by_module[dependant_module] == nil do
        acc
      else
        [dependent | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp maybe_recompile(updated_deps, deps, type_hash_by_dependant_module, preconds_hash_by_module, verbose?) do
    {modules_to_recompile, sources_to_recompile} =
      updated_deps
      |> sources_with_changed_dependants_type_hash(type_hash_by_dependant_module)
      |> add_sources_for_modules_of_changed_dependants(updated_deps, deps)
      |> add_sources_for_modules_of_changed_preconditions(updated_deps, preconds_hash_by_module)
      |> add_sources_dependind_on_changed_sources(deps)
      |> Enum.unzip()

    if Enum.empty?(sources_to_recompile) do
      {:ok, []}
    else
      beams_to_recompile =
        Enum.map(modules_to_recompile, fn module ->
          module |> :code.which() |> List.to_string()
        end)

      touch_and_recompile(Enum.uniq(sources_to_recompile), Enum.uniq(beams_to_recompile), verbose?)
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
    Enum.any?(dependants, fn {module, old_hash, _precond_old_hash} ->
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

  defp add_sources_for_modules_of_changed_preconditions(sources_by_module, updated_deps, preconds_hash_by_module) do
    changed_sources =
      Enum.reduce(updated_deps, %{}, fn {module, {path, dependants}}, acc ->
        any_hash_differs? = Enum.any?(dependants, fn {module, _type_hash, preconds_hash} -> preconds_hash != preconds_hash_by_module[module] end)

        if any_hash_differs? do
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
        Enum.reduce(dependants, acc, fn {dependant_module, _type_old_hash, _precond_old_hash}, acc ->
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

  defp touch_and_recompile(sources_to_recompile, beams_to_recompile, verbose?) do
    # Have to wait 1 second to touch files with later epoch time
    # and make elixir compiler to percept them as stale files.
    Process.sleep(1000)

    if verbose? do
      IO.puts("""
      Domo marks files for recompilation by touching:
      #{Enum.join(sources_to_recompile, "\n")}\
      """)
    end

    Enum.each(sources_to_recompile, &File.touch!/1)

    if verbose? do
      IO.puts("""
      Domo meets Elixir's criteria for recompilation by removing:
      #{Enum.join(beams_to_recompile, "\n")}\
      """)
    end

    # Since v1.13 Elixir expects missing .beam to recompile from source
    Enum.each(beams_to_recompile, &File.rm/1)

    ElixirTask.recompile_with_elixir(verbose?)
  end
end
