defmodule Mix.Tasks.Compile.Domo do
  @moduledoc false

  use Mix.Task.Compiler

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Cleaner
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.TypeEnsurerFactory.Resolver
  alias Domo.MixProjectHelper
  alias Mix.Task.Compiler.Diagnostic

  @recursive true
  @plan_manifest "type_resolving_plan.domo"
  @types_manifest "resolved_types.domo"
  @deps_manifest "modules_deps.domo"
  @generated_code_directory "/domo_generated_code"

  @impl true
  def run(_args) do
    project = MixProjectHelper.global_stub() || Mix.Project
    plan_path = manifest_path(project, :plan)
    types_path = manifest_path(project, :types)
    deps_path = manifest_path(project, :deps)
    code_path = generated_code_path(project)

    ResolvePlanner.ensure_flushed_and_stopped(plan_path)

    prev_ignore_module_conflict = Map.get(Code.compiler_options(), :ignore_module_conflict, false)
    Code.compiler_options(ignore_module_conflict: true)

    result = build_ensurer_modules({plan_path, types_path, deps_path, code_path})

    Code.compiler_options(ignore_module_conflict: prev_ignore_module_conflict)

    maybe_print_errors(result)

    result
  end

  defp build_ensurer_modules(paths) do
    {plan_path, types_path, deps_path, code_path} = paths

    Cleaner.rmdir_if_exists!(code_path)

    with {:deps, {:ok, _modules, deps_warns}} <-
           {:deps, DependencyResolver.maybe_recompile_depending_structs(deps_path)},
         :ok <-
           Resolver.resolve(plan_path, types_path, deps_path),
         {:ok, type_ensurer_paths} <-
           Generator.generate(types_path, code_path),
         {:ens, {:ok, modules, ens_warns}} <-
           {:ens, Generator.compile(type_ensurer_paths)} do
      Cleaner.rm!([plan_path, types_path])
      warnings = format_warnings([deps_warns, ens_warns])
      {if(Enum.empty?(modules), do: :noop, else: :ok), warnings}
    else
      {:error, [%Error{compiler_module: Resolver, message: :no_plan}]} -> {:noop, []}
      {source, {:error, errors, _warns}} -> {:error, Enum.map(errors, &diagnostic(source, &1))}
      {:error, errors} when is_list(errors) -> {:error, Enum.map(errors, &diagnostic(&1))}
      {:error, error} -> {:error, [diagnostic(error)]}
    end
  end

  defp format_warnings(warns) do
    warns
    |> List.flatten()
    |> Enum.map(fn {path, position, message} ->
      %Diagnostic{
        compiler_name: "elixir",
        file: path,
        position: position,
        message: message,
        severity: :warning
      }
    end)
  end

  defp diagnostic(%Error{compiler_module: Resolver, struct_module: nil} = error) do
    message = """
    #{module_to_string(error.compiler_module)} failed due to #{inspect(error.message)}.\
    """

    diagnostic(error.file, message)
  end

  defp diagnostic(%Error{compiler_module: Resolver} = error) do
    message = """
    #{module_to_string(error.compiler_module)} failed to resolve fields type \
    of the #{module_to_string(error.struct_module)} struct due to #{inspect(error.message)}.\
    """

    diagnostic(error.file, message)
  end

  defp diagnostic(%Error{compiler_module: Generator} = error) do
    message = """
    #{module_to_string(error.compiler_module)} failed to generate \
    TypeEnsurer module code due to #{inspect(error.message)}.\
    """

    diagnostic(error.file, message)
  end

  defp diagnostic(:ens, {path, _line, error}) do
    message = """
    Elixir compiler failed to compile a TypeEnsurer module code due to \
    #{error}\
    """

    diagnostic(path, message)
  end

  defp diagnostic(:deps, {path, _line, error}) do
    message = """
    Elixir compiler launched by DependencyResolver failed due to \
    #{error}\
    """

    diagnostic(path, message)
  end

  defp diagnostic(file, message) do
    %Diagnostic{
      compiler_name: "domo",
      file: file,
      message: message,
      position: 1,
      severity: :error
    }
  end

  defp module_to_string(module) do
    {:__aliases__, [alias: false], module_parts} = Alias.atom_to_alias(module)

    module_parts
    |> Enum.map(&Atom.to_string(&1))
    |> Enum.join(".")
  end

  def generated_code_path(mix_project) do
    Path.join(mix_project.build_path(), @generated_code_directory)
  end

  defp maybe_print_errors({:error, diagnostics}) do
    diagnostics
    |> List.wrap()
    |> Enum.each(&print_error(&1.file, &1.message))
  end

  defp maybe_print_errors(_), do: nil

  defp print_error(file, reason) do
    IO.write([
      "\n== Type ensurer compilation error in file #{Path.relative_to_cwd(file)} ==\n",
      ["** ", reason, ?\n]
    ])
  end

  @impl true
  def manifests, do: [@plan_manifest, @types_manifest]
  def deps_manifest, do: @deps_manifest

  def manifest_path(mix_project, manifest_kind) do
    Path.join(mix_project.build_path(), manifest(manifest_kind))
  end

  defp manifest(kind) do
    case kind do
      :plan -> @plan_manifest
      :types -> @types_manifest
      :deps -> @deps_manifest
    end
  end

  @impl true
  def clean do
    project = MixProjectHelper.global_stub() || Mix.Project
    plan_path = manifest_path(project, :plan)
    types_path = manifest_path(project, :types)
    deps_path = manifest_path(project, :deps)
    code_path = generated_code_path(project)

    File.rm(plan_path)
    File.rm(types_path)
    File.rm(deps_path)
    Cleaner.rmdir_if_exists!(code_path)
  end
end
