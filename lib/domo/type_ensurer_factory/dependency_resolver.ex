defmodule Domo.TypeEnsurerFactory.DependencyResolver do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Error
  alias Kernel.ParallelCompiler

  def maybe_recompile_depending_structs(deps_path, file_module \\ File) do
    with {:read_deps, {:ok, content}} <- {:read_deps, file_module.read(deps_path)},
         {:decode_deps, {:ok, deps}} <- {:decode_deps, binary_to_term(content)},
         deps = reject_deps_by_missing_source(deps),
         deps_mtime = mtime(deps_path),
         {:upd_deps, :ok} <- {:upd_deps, file_module.write(deps_path, term_to_binary(deps))},
         {:touch_deps, :ok} <- {:touch_deps, file_module.touch(deps_path, deps_mtime)} do
      deps
      |> Enum.reduce([], &maybe_accumulate_compilation_path(&1, deps_mtime, &2))
      |> Enum.uniq()
      |> touch_files()
      |> ParallelCompiler.compile()
    else
      {:read_deps, {:error, :enoent}} ->
        {:ok, [], []}

      {operation, {:error, error}} ->
        %Error{
          compiler_module: __MODULE__,
          file: deps_path,
          struct_module: nil,
          message: {operation, error}
        }
    end
  end

  defp binary_to_term(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _error -> {:error, :malformed_binary}
    end
  end

  defp term_to_binary(term) do
    :erlang.term_to_binary(term)
  end

  defp maybe_accumulate_compilation_path({module, {path, dependants}}, max_mtime, path_list) do
    dependants_beams = Enum.map(dependants, &beam_path/1)
    module_beam = beam_path(module)

    if any_file_missing?(dependants_beams) or
         (modified_earlier_mtime?(module_beam, max_mtime) and
            any_modified_later?(dependants_beams, module_beam)) do
      [path | path_list]
    else
      path_list
    end
  end

  defp beam_path(module) do
    compile_path = Mix.Project.compile_path()
    Path.join(compile_path, to_string(module) <> ".beam")
  end

  defp any_file_missing?(paths_list) do
    not Enum.all?(paths_list, &File.exists?/1)
  end

  defp any_modified_later?(dependants_paths, module_path) do
    dependants_paths
    |> Enum.map(&modified_later?(&1, module_path))
    |> Enum.any?()
  end

  defp modified_later?(path1, path2) do
    mtime(path1) > mtime(path2)
  end

  defp modified_earlier_mtime?(path, max_mtime) do
    mtime(path) < max_mtime
  end

  defp mtime(path) do
    %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
    mtime
  end

  defp touch_files(paths_list) do
    Enum.map(paths_list, fn path ->
      File.touch!(path)
      path
    end)
  end

  defp reject_deps_by_missing_source(deps) do
    deps
    |> Enum.filter(&source_exists?/1)
    |> Enum.into(%{})
  end

  defp source_exists?({_module, {source, _attrs}}), do: File.exists?(source)
end
