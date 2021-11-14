defmodule Mix.Tasks.Compile.DomoCompiler do
  @moduledoc false

  use Mix.Task.Compiler

  alias Domo.TypeEnsurerFactory
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.BatchEnsurer
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
  @preconds_manifest "preconds.domo"
  @deps_manifest "modules_deps.domo"
  @generated_code_directory "/domo_generated_code"
  @standard_lib_modules [
    Date,
    Date.Range,
    DateTime,
    File.Stat,
    File.Stream,
    GenEvent.Stream,
    IO.Stream,
    Macro.Env,
    NaiveDateTime,
    Range,
    Regex,
    Task,
    Time,
    URI,
    Version
  ]
  @optional_lib_modules [Decimal]
  @treat_as_any_optional_lib_modules [Ecto.Schema.Metadata]

  @impl true
  def run(args) do
    project = MixProjectHelper.global_stub() || Mix.Project
    plan_path = manifest_path(project, :plan)
    preconds_path = manifest_path(project, :preconds)
    types_path = manifest_path(project, :types)
    deps_path = manifest_path(project, :deps)
    code_path = generated_code_path(project)

    prev_ignore_module_conflict = Map.get(Code.compiler_options(), :ignore_module_conflict, false)
    Code.compiler_options(ignore_module_conflict: true)

    paths = {plan_path, preconds_path, types_path, deps_path, code_path}
    verbose? = Enum.member?(args, "--verbose")
    result = build_ensurer_modules(paths, verbose?)

    Code.compiler_options(ignore_module_conflict: prev_ignore_module_conflict)

    maybe_print_errors(result)

    result
  end

  def generated_code_path(mix_project) do
    Path.join(mix_project.build_path(), @generated_code_directory)
  end

  defp build_ensurer_modules(paths, verbose?) do
    {plan_path, preconds_path, types_path, deps_path, code_path} = paths

    maybe_collect_types_for_lib_structs(plan_path, preconds_path)
    stop_and_flush_planner(plan_path, verbose?)

    if File.exists?(plan_path) do
      maybe_collect_lib_structs_to_treat_as_any(plan_path, preconds_path)
      stop_and_flush_planner(plan_path, verbose?)
    end

    with {:ok, deps_warns} <- recompile_depending_structs(deps_path, preconds_path, verbose?),
         stop_and_flush_planner(plan_path, verbose?),
         maybe_remove_ensurers_code(plan_path, code_path, verbose?),
         :ok <- resolve_types(plan_path, preconds_path, types_path, deps_path, verbose?),
         {:ok, type_ensurer_paths} <- generate_type_ensurers(types_path, code_path),
         {:ok, {modules, ens_warns}} <- compile_type_ensurers(type_ensurer_paths, verbose?),
         :ok <- ensure_struct_defaults(plan_path),
         :ok <- ensure_structs_integrity(plan_path) do
      Cleaner.rm!([plan_path, types_path])

      if verbose? do
        IO.write("""
        Domo removed plan file #{plan_path} and types file #{types_path}.
        """)
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
          errors when is_list(errors) -> {:error, Enum.map(errors, &diagnostic(&1))}
          error -> {:error, [diagnostic(error)]}
        end
    end
  end

  defp maybe_collect_types_for_lib_structs(plan_path, preconds_path) do
    modules = @standard_lib_modules ++ Enum.reduce(@optional_lib_modules, [], &if(TypeEnsurerFactory.ensure_loaded?(&1), do: [&1 | &2], else: &2))

    collectable_modules = Enum.filter(modules, &(TypeEnsurerFactory.has_type_ensurer?(&1) == false))

    unless Enum.empty?(collectable_modules) do
      {:ok, _pid} = ResolvePlanner.ensure_started(plan_path, preconds_path)

      modules_string = collectable_modules |> Enum.map(&Alias.atom_to_string/1) |> Enum.join(", ")

      IO.write("""
      Domo makes type ensures for standard lib modules #{modules_string}.
      """)

      Enum.each(collectable_modules, fn module ->
        env = simulated_env(module)
        {_module, bytecode, _path} = :code.get_object_code(module)
        TypeEnsurerFactory.collect_types_for_domo_compiler(plan_path, env, bytecode)
      end)
    end
  end

  defp maybe_collect_lib_structs_to_treat_as_any(plan_path, preconds_path) do
    modules = Enum.reduce(@treat_as_any_optional_lib_modules, [], &if(TypeEnsurerFactory.ensure_loaded?(&1), do: [&1 | &2], else: &2))

    unless Enum.empty?(modules) do
      {:ok, _pid} = ResolvePlanner.ensure_started(plan_path, preconds_path)

      modules_string = modules |> Enum.map(&Alias.atom_to_string/1) |> Enum.join(", ")

      IO.write("""
      Domo will treat the following modules t() type as any() #{modules_string}
      """)

      module_t_types = Enum.map(modules, &{&1, [:t]})

      TypeEnsurerFactory.collect_types_to_treat_as_any(plan_path, nil, module_t_types, nil)
    end
  end

  defp simulated_env(module) do
    %{__ENV__ | module: module}
  end

  defp stop_and_flush_planner(plan_path, verbose?) do
    ResolvePlanner.ensure_flushed_and_stopped(plan_path, verbose?)
  end

  defp maybe_remove_ensurers_code(plan_path, code_path, verbose?) do
    if File.exists?(plan_path) do
      Cleaner.rmdir_if_exists!(code_path)

      if verbose? do
        IO.write("""
        Domo removed directory with generated code if existed #{code_path}.
        """)
      end
    end
  end

  defp recompile_depending_structs(deps_path, preconds_path, verbose?) do
    case DependencyResolver.maybe_recompile_depending_structs(deps_path, preconds_path, verbose?: verbose?) do
      {:ok, _warnings} = ok -> ok
      {:noop, []} -> {:ok, []}
      {:error, ex_errors, ex_warnings} -> {:error, {:deps, {ex_errors, ex_warnings}}}
      {:error, message} -> {:error, {:deps, message}}
    end
  end

  defp resolve_types(plan_path, preconds_path, types_path, deps_path, verbose?) do
    case Resolver.resolve(plan_path, preconds_path, types_path, deps_path, verbose?) do
      :ok -> :ok
      {:error, message} -> {:error, {:resolve, message}}
    end
  end

  defp generate_type_ensurers(types_path, code_path) do
    case Generator.generate(types_path, code_path) do
      {:ok, _type_ensurer_paths} = ok -> ok
      {:error, message} -> {:error, {:generate, message}}
    end
  end

  defp compile_type_ensurers(type_ensurer_paths, verbose?) do
    case Generator.compile(type_ensurer_paths, verbose?) do
      {:ok, modules, te_warns} -> {:ok, {modules, te_warns}}
      {:error, ex_errors, ex_warnings} -> {:error, {:compile, {ex_errors, ex_warnings}}}
      {:error, message} -> {:error, {:compile, message}}
    end
  end

  defp ensure_struct_defaults(plan_path) do
    case BatchEnsurer.ensure_struct_defaults(plan_path) do
      :ok -> :ok
      {:error, message} -> {:error, {:batch_ensurer, {[message], []}}}
    end
  end

  defp ensure_structs_integrity(plan_path) do
    case BatchEnsurer.ensure_struct_integrity(plan_path) do
      :ok -> :ok
      {:error, message} -> {:error, {:batch_ensurer, {[message], []}}}
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

  defp diagnostic(file, message) do
    %Diagnostic{
      compiler_name: "Domo",
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
    Path.join(mix_project.build_path(), manifest(manifest_kind))
  end

  defp manifest(kind) do
    case kind do
      :plan -> @plan_manifest
      :preconds -> @preconds_manifest
      :types -> @types_manifest
      :deps -> @deps_manifest
    end
  end

  @impl true
  def clean do
    project = MixProjectHelper.global_stub() || Mix.Project
    plan_path = manifest_path(project, :plan)
    types_path = manifest_path(project, :types)
    preconds_path = manifest_path(project, :preconds)
    deps_path = manifest_path(project, :deps)
    code_path = generated_code_path(project)

    File.rm(plan_path)
    File.rm(types_path)
    File.rm(preconds_path)
    File.rm(deps_path)
    Cleaner.rmdir_if_exists!(code_path)
  end
end
