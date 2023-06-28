defmodule Mix.Tasks.Compile.DomoCompiler do
  @moduledoc false

  use Mix.Task.Compiler

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.BatchEnsurer
  alias Domo.TypeEnsurerFactory.Cleaner
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.TypeEnsurerFactory.Resolver
  alias Mix.Task.Compiler.Diagnostic

  @recursive true
  @plan_manifest "type_resolving_plan.domo"
  @types_manifest "resolved_types.domo"
  @preconds_manifest "preconds.domo"
  @deps_manifest "modules_deps.domo"
  @ecto_assocs_manifest "ecto_assocs.domo"
  @generated_code_directory "/domo_generated_code"

  @mix_project Application.compile_env(:domo, :mix_project, Mix.Project)

  @impl true
  def run(args) do
    start_plan_collection(args)

    Mix.Task.Compiler.after_compiler(:elixir, fn status_diagnostic ->
      __MODULE__.process_plan(status_diagnostic, args)
    end)

    {:ok, []}
  end

  def start_plan_collection(args \\ []) do
    plan_path = manifest_path(@mix_project, :plan)
    preconds_path = manifest_path(@mix_project, :preconds)
    verbose? = Enum.member?(args, "--verbose")
    {:ok, _pid} = ResolvePlanner.ensure_started(plan_path, preconds_path, verbose?: verbose?)

    CodeEvaluation.put_plan_collection(true)
  end

  def process_plan({:error, _diagnostics} = error, _args) do
    stop_plan_collection()
    error
  end

  def process_plan(status_diagnostic, args) do
    plan_path = manifest_path(@mix_project, :plan)
    preconds_path = manifest_path(@mix_project, :preconds)
    types_path = manifest_path(@mix_project, :types)
    deps_path = manifest_path(@mix_project, :deps)
    ecto_assocs_path = manifest_path(@mix_project, :ecto_assocs)
    code_path = generated_code_path(@mix_project)

    TypeEnsurerFactory.maybe_collect_lib_structs_to_treat_as_any_to_existing_plan(plan_path)
    TypeEnsurerFactory.print_global_anys(plan_path)

    stop_plan_collection()

    prev_ignore_module_conflict = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    paths = {plan_path, preconds_path, types_path, deps_path, ecto_assocs_path, code_path}
    verbose? = Enum.member?(args, "--verbose")
    result = build_ensurer_modules(paths, verbose?)

    Code.put_compiler_option(:ignore_module_conflict, prev_ignore_module_conflict)

    maybe_print_errors(result)

    merge_diagnostics(result, status_diagnostic)
  end

  defp merge_diagnostics({domo_status, domo_diagnostics}, {_elixir_status, elixir_diagnostics}) when domo_status in [:ok, :error] do
    {domo_status, domo_diagnostics ++ elixir_diagnostics}
  end

  defp merge_diagnostics({domo_status, domo_diagnostics}, status) when domo_status in [:ok, :error] and is_atom(status) do
    {domo_status, domo_diagnostics}
  end

  defp merge_diagnostics({:noop, domo_diagnostics}, {elixir_status, elixir_diagnostics}) do
    {elixir_status, domo_diagnostics ++ elixir_diagnostics}
  end

  defp merge_diagnostics({:noop, domo_diagnostics}, elixir_status) do
    {elixir_status, domo_diagnostics}
  end

  def stop_plan_collection do
    CodeEvaluation.put_plan_collection(false)

    plan_path = manifest_path(@mix_project, :plan)
    ResolvePlanner.ensure_flushed_and_stopped(plan_path)
  end

  def generated_code_path(mix_project) do
    Path.join(mix_project.manifest_path(), @generated_code_directory)
  end

  defp build_ensurer_modules(paths, verbose?) do
    {plan_path, preconds_path, types_path, deps_path, ecto_assocs_path, code_path} = paths

    with {:ok, deps_warns} <- TypeEnsurerFactory.recompile_depending_structs(plan_path, deps_path, preconds_path, verbose?),
         remove_ensurers_code_having_plan(plan_path, code_path, verbose?),
         :ok <- TypeEnsurerFactory.resolve_types(plan_path, preconds_path, types_path, deps_path, ecto_assocs_path, verbose?),
         {:ok, type_ensurer_paths} <- TypeEnsurerFactory.generate_type_ensurers(types_path, ecto_assocs_path, code_path, verbose?),
         {:ok, {modules, ens_warns}} <- TypeEnsurerFactory.compile_type_ensurers(type_ensurer_paths, verbose?),
         :ok <- TypeEnsurerFactory.ensure_struct_defaults(plan_path, verbose?),
         :ok <- TypeEnsurerFactory.ensure_structs_integrity(plan_path, verbose?) do
      Cleaner.rm!([plan_path, types_path])

      if verbose? do
        IO.puts("Domo removed plan file #{plan_path} and types file #{types_path}.")
      end

      result = if(Enum.empty?(modules), do: :noop, else: :ok)
      warnings = format_warnings([deps_warns, ens_warns])
      {result, warnings}
    else
      {:error, {source, message}} ->
        if source == :batch_ensurer do
          Cleaner.rm!([plan_path, types_path])
        end

        case message do
          [%Error{compiler_module: Resolver, message: :no_plan}] -> {:noop, []}
          {ex_errors, _ex_warns} -> {:error, Enum.map(ex_errors, &diagnostic(source, &1))}
          {_, _, _} = file_line_msg -> {:error, [diagnostic(source, file_line_msg)]}
          errors when is_list(errors) -> {:error, Enum.map(errors, &diagnostic(&1))}
          error -> {:error, [diagnostic(error)]}
        end
    end
  end

  defp remove_ensurers_code_having_plan(plan_path, code_path, verbose?) do
    if File.exists?(plan_path) do
      Cleaner.rmdir_if_exists!(code_path)

      if verbose? do
        IO.puts("Domo removed directory with generated code if existed #{code_path}.")
      end
    end
  end

  defp format_warnings(warns) do
    warns
    |> List.flatten()
    |> Enum.map(&wrap_diagnostic/1)
  end

  defp wrap_diagnostic(%Diagnostic{} = diagnostic) do
    diagnostic
  end

  defp wrap_diagnostic({path, position, message}) do
    %Diagnostic{
      compiler_name: "Elixir",
      file: path,
      position: position,
      message: message,
      severity: :warning
    }
  end

  defp diagnostic(%Error{compiler_module: Resolver, struct_module: nil} = error) do
    message = """
    #{module_to_string(error.compiler_module)} failed due to #{inspect(error.message)}.\
    """

    diagnostic(error.file, message)
  end

  defp diagnostic(%Error{compiler_module: Resolver, message: {:parametrized_type_not_supported, tuple}} = error) do
    {module, full_type_string} = tuple

    message = """
    #{module_to_string(error.compiler_module)} failed to resolve fields type \
    of the #{module_to_string(error.struct_module)} struct due to parametrized type \
    referenced by #{full_type_string} is not supported.\
    Please, define custom user type and validate fields of #{module_to_string(module)} \
    in the precondition function attached like the following:

        @type remote_type :: term()
        precond remote_type: &validate_fields_of_struct/1

    Then reference remote_type instead of #{full_type_string}
    """

    diagnostic(error.file, message)
  end

  defp diagnostic(%Error{compiler_module: Resolver, message: {:self_referencing_type, type_string}} = error) do
    message = """
    #{module_to_string(error.compiler_module)} failed to resolve fields type \
    of the #{module_to_string(error.struct_module)} struct because of the self referencing type #{type_string}. \
    Only struct types referencing themselves are supported.\
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

  defp diagnostic(%Error{compiler_module: DependencyResolver} = error) do
    message = """
    #{module_to_string(error.compiler_module)} failed to recompile depending structs \
    due to #{inspect(error.message)}.\
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

  defp diagnostic(%Error{compiler_module: BatchEnsurer} = error) do
    message = "#{inspect(error.compiler_module)} failed due to #{inspect(error.message)}"

    diagnostic(error.file, message)
  end

  defp diagnostic(%Diagnostic{} = diagnostic) do
    diagnostic
  end

  defp diagnostic(:compile, {path, _line, error}) do
    message = """
    Elixir compiler failed to compile a TypeEnsurer module code due to \
    #{error}\
    """

    diagnostic(path, message)
  end

  defp diagnostic(:batch_ensurer, {path, line, error}) do
    %Diagnostic{
      compiler_name: "Elixir",
      file: path,
      message: error,
      position: line,
      severity: :error
    }
  end

  defp diagnostic(source, message) do
    %Diagnostic{
      compiler_name: "Domo",
      file: source,
      message: message,
      position: 1,
      severity: :error
    }
  end

  defp module_to_string(module) do
    {:__aliases__, [alias: false], module_parts} = Alias.atom_to_alias(module)
    Enum.map_join(module_parts, ".", &Atom.to_string(&1))
  end

  defp maybe_print_errors({:error, diagnostics}) do
    diagnostics
    |> List.wrap()
    |> Enum.each(&print_error(&1))
  end

  defp maybe_print_errors(_), do: nil

  defp print_error(%Diagnostic{compiler_name: "Domo"} = diagnostic) do
    IO.write([
      "\n== Type ensurer compilation error in file #{Path.relative_to_cwd(diagnostic.file)} ==\n",
      ["** ", unescape_characters(diagnostic.message), ?\n]
    ])
  end

  defp print_error(%Diagnostic{compiler_name: "Elixir"} = diagnostic) do
    IO.write([
      "\n== Compilation error in file #{Path.relative_to_cwd(diagnostic.file)}:#{inspect(diagnostic.position)} ==\n",
      ["** ", unescape_characters(diagnostic.message), ?\n]
    ])
  end

  defp unescape_characters(message) do
    message
    |> String.replace("\\n", "\n")
    |> String.replace("\\\"", "\"")
  end

  @impl true
  def manifests, do: [@plan_manifest, @types_manifest]
  def deps_manifest, do: @deps_manifest
  def preconds_manifest, do: @preconds_manifest

  def manifest_path(mix_project, manifest_kind) do
    Path.join(mix_project.manifest_path(), manifest(manifest_kind))
  end

  defp manifest(kind) do
    case kind do
      :plan -> @plan_manifest
      :preconds -> @preconds_manifest
      :types -> @types_manifest
      :deps -> @deps_manifest
      :ecto_assocs -> @ecto_assocs_manifest
    end
  end

  @impl true
  def clean do
    plan_path = manifest_path(@mix_project, :plan)
    types_path = manifest_path(@mix_project, :types)
    preconds_path = manifest_path(@mix_project, :preconds)
    deps_path = manifest_path(@mix_project, :deps)
    code_path = generated_code_path(@mix_project)

    File.rm(plan_path)
    File.rm(types_path)
    File.rm(preconds_path)
    File.rm(deps_path)
    Cleaner.rmdir_if_exists!(code_path)
  end
end
