defmodule Domo.TypeEnsurerFactory do
  @moduledoc false

  alias Domo.Raises
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.BatchEnsurer
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.TypeEnsurerFactory.Resolver

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
  @optional_lib_modules [Decimal, Ecto.Association.NotLoaded]
  @treat_as_any_optional_lib_modules [Ecto.Schema.Metadata]

  defdelegate module_name_string(module), to: Alias, as: :atom_to_string
  defdelegate start_resolve_planner(plan_path, preconds_path, opts), to: ResolvePlanner, as: :ensure_started
  defdelegate strop_resolve_planner(plan_path), to: ResolvePlanner, as: :stop
  defdelegate get_plan_state(path), to: ResolvePlanner
  defdelegate clean_plan(path), to: ResolvePlanner
  defdelegate get_dependants(path, module), to: ResolvePlanner
  defdelegate type_ensurer(module), to: ModuleInspector
  defdelegate has_type_ensurer?(module), to: ModuleInspector

  def register_dependants_from(path, dependencies_by_module) do
    dependants_by_module =
      dependencies_by_module
      |> Enum.reduce(%{}, fn {module, {_path, dependencies}}, acc ->
        Enum.reduce(dependencies, acc, fn {dependency, _, _}, acc ->
          list = Map.get(acc, dependency, [])
          Map.put(acc, dependency, [module | list])
        end)
      end)
      |> Enum.map(fn {module, list} -> {module, Enum.reverse(list)} end)
      |> Enum.into(%{})

    ResolvePlanner.register_many_dependants(path, dependants_by_module)
  end

  def maybe_collect_types_for_stdlib_structs(plan_path) do
    modules = @standard_lib_modules ++ Enum.reduce(@optional_lib_modules, [], &if(ModuleInspector.ensure_loaded?(&1), do: [&1 | &2], else: &2))

    collectable_modules = Enum.filter(modules, &(ModuleInspector.has_type_ensurer?(&1) == false))

    unless Enum.empty?(collectable_modules) do
      modules_string = Enum.map_join(collectable_modules, ", ", &Alias.atom_to_string/1)

      IO.puts("Domo makes type ensures for standard lib modules #{modules_string}.")

      Enum.each(collectable_modules, fn module ->
        env = simulated_env(module)
        {_module, bytecode, _path} = :code.get_object_code(module)
        collect_types_for_domo_compiler(plan_path, env, bytecode)
      end)
    end
  end

  defp simulated_env(module) do
    %{__ENV__ | module: module}
  end

  def collect_types_for_domo_compiler(plan_path, env, bytecode) do
    :ok = ResolvePlanner.keep_module_environment(plan_path, env.module, env)

    quoted_type =
      bytecode
      |> ModuleInspector.fetch_direct_types()
      |> elem(1)
      |> Enum.find_value(fn
        {kind, {:t, _, _} = t} when kind in [:type, :opaque] -> t
        _ -> nil
      end)
      |> Code.Typespec.type_to_quoted()

    {:"::", _, [{:t, _, _}, {:%, _, [_module_name, {:%{}, _, field_type_list}]} = quoted_definition]} = quoted_type

    t_reflection = Macro.to_string(quoted_definition)
    :ok = ResolvePlanner.keep_struct_t_reflection(plan_path, env.module, t_reflection)

    if Enum.empty?(field_type_list) do
      ResolvePlanner.plan_empty_struct(plan_path, env.module)
    else
      Enum.each(field_type_list, fn {field, quoted_type} ->
        :ok ==
          ResolvePlanner.plan_types_resolving(
            plan_path,
            env.module,
            field,
            quoted_type
          )
      end)
    end
  end

  def plan_empty_struct(plan_path, env) do
    :ok = ResolvePlanner.keep_module_environment(plan_path, env.module, env)
    ResolvePlanner.plan_empty_struct(plan_path, env.module)
  end

  def register_in_memory_types(module, bytecode) do
    {:ok, types_list} = ModuleInspector.fetch_direct_types(bytecode)
    :ok = ResolvePlanner.register_types(:in_memory, module, types_list)
  end

  def maybe_collect_lib_structs_to_treat_as_any_to_existing_plan(plan_path) do
    modules = Enum.reduce(@treat_as_any_optional_lib_modules, [], &if(ModuleInspector.ensure_loaded?(&1), do: [&1 | &2], else: &2))

    unless Enum.empty?(modules) do
      module_t_types = Enum.map(modules, &{&1, [:t]})
      collect_types_to_treat_as_any(plan_path, nil, module_t_types, nil)
    end
  end

  def collect_types_to_treat_as_any(plan_path, module, global_anys, local_anys) do
    unless is_nil(global_anys) do
      global_anys_map = cast_keyword_to_map_of_lists_by_module(global_anys)
      ResolvePlanner.keep_global_remote_types_to_treat_as_any(plan_path, global_anys_map)
    end

    unless is_nil(local_anys) do
      local_anys_map = cast_keyword_to_map_of_lists_by_module(local_anys)
      ResolvePlanner.keep_remote_types_to_treat_as_any(plan_path, module, local_anys_map)
    end
  end

  defp cast_keyword_to_map_of_lists_by_module(kw_list) do
    kw_list
    |> Enum.map(fn {key, value} -> {Module.concat(Elixir, key), List.wrap(value)} end)
    |> Enum.into(%{})
  end

  def print_global_anys(plan_path) do
    {:ok, anys} = ResolvePlanner.types_treated_as_any(plan_path)
    global_anys = Map.get(anys, :global, %{})

    unless Enum.empty?(global_anys) do
      module_type_list =
        global_anys
        |> Enum.reduce([], fn {module, types}, acc ->
          Enum.reduce(types, acc, fn type, acc ->
            module_type = Alias.string_by_concat(module, type) <> "()"
            [module_type | acc]
          end)
        end)
        |> Enum.reverse()
        |> Enum.join(", ")

      IO.puts("Domo will treat the following types as any() globally: #{module_type_list}.")
    end
  end

  def plan_struct_defaults_ensurance(plan_path, env) do
    global_ensure_struct_defaults = Application.get_env(:domo, :ensure_struct_defaults, not Application.get_env(:domo, :skip_defaults, false))

    module = env.module
    opts = Module.get_attribute(module, :domo_options, [])
    skip_defaults = Keyword.get(opts, :skip_defaults, not Keyword.get(opts, :ensure_struct_defaults, global_ensure_struct_defaults))
    in_struct? = ModuleInspector.struct_module?(module)

    unless skip_defaults or not in_struct? do
      do_plan_struct_defaults_ensurance(plan_path, env)
    end
  end

  defp do_plan_struct_defaults_ensurance(plan_path, env) do
    default_kv =
      env.module
      |> ModuleInspector.default_kv_from_struct(env)
      |> Enum.sort_by(fn {key, _value} -> key end)

    :ok ==
      ResolvePlanner.plan_struct_defaults_ensurance(
        plan_path,
        env.module,
        default_kv,
        to_string(env.file),
        env.line
      )
  end

  def plan_struct_integrity_ensurance(plan_path, module, enumerable) do
    {:current_stacktrace, calls} = Process.info(self(), :current_stacktrace)

    {_, _, _, file_line} = Enum.find(calls, Enum.at(calls, 3), fn {_, module, _, _} -> module == :__MODULE__ end)

    :ok ==
      ResolvePlanner.plan_struct_integrity_ensurance(
        plan_path,
        module,
        enumerable,
        to_string(file_line[:file]),
        file_line[:line]
      )
  end

  def plan_precond_checks(plan_path, env, bytecode) do
    module_type_names =
      bytecode
      |> ModuleInspector.fetch_direct_types()
      |> elem(1)
      |> Enum.map(fn {kind, {name, _, _}} when kind in [:type, :opaque] -> name end)

    module = env.module
    precond_name_description = Module.get_attribute(module, :domo_precond)

    precond_type_names =
      precond_name_description
      |> Enum.unzip()
      |> elem(0)

    missing_type = any_missing_type(precond_type_names, module_type_names)

    if missing_type do
      Raises.raise_nonexistent_type_for_precond(missing_type)
    end

    :ok = ResolvePlanner.plan_precond_checks(plan_path, module, precond_name_description)
  end

  defp any_missing_type(precond_type_names, module_type_names) do
    precond_type_names = MapSet.new(precond_type_names)
    module_type_names = MapSet.new(module_type_names)

    precond_type_names
    |> MapSet.difference(module_type_names)
    |> MapSet.to_list()
    |> List.first()
  end

  def resolve_plan(plan, preconds, verbose?) do
    resolvable = %{
      fields: plan.filed_types_to_resolve,
      preconds: preconds,
      envs: plan.environments,
      t_reflections: plan.t_reflections,
      anys_by_module: plan.remote_types_as_any_by_module
    }

    Resolver.resolve_plan(resolvable, :in_memory, verbose?)
  end

  def resolve_types(plan_path, preconds_path, types_path, deps_path, ecto_assocs_path, t_reflections_path, verbose?) do
    if verbose? do
      IO.puts("Domo resolve collected types. #{plan_path}")
    end

    case Resolver.resolve(plan_path, preconds_path, types_path, deps_path, ecto_assocs_path, t_reflections_path, verbose?) do
      :ok -> :ok
      {:error, message} -> {:error, {:resolve, message}}
    end
  end

  def build_type_ensurers(module_filed_types, ecto_assocs_by_module, t_reflection_by_module, verbose?) do
    if verbose? do
      IO.puts("Domo generates TypeEnsurer modules source code and load them into memory.")
    end

    module_filed_types
    |> Enum.map(fn {module, field_types} ->
      ecto_assocs = Map.get(ecto_assocs_by_module, module, [])
      t_reflection = Map.get(t_reflection_by_module, module)
      Generator.generate_one(module, field_types, ecto_assocs, t_reflection)
    end)
    |> Code.eval_quoted()

    :ok
  end

  def invalidate_type_ensurers(modules) do
    modules
    |> Enum.map(&Generator.generate_invalid(&1))
    |> Code.eval_quoted()
  end

  def generate_type_ensurers(types_path, ecto_assocs_path, t_reflections_path, code_path, verbose?) do
    if verbose? do
      IO.puts("Domo generates TypeEnsurer modules source code.")
    end

    case Generator.generate(types_path, ecto_assocs_path, t_reflections_path, code_path) do
      {:ok, _type_ensurer_paths} = ok -> ok
      %Error{} = error -> {:error, {:generate, error}}
    end
  end

  def compile_type_ensurers(type_ensurer_paths, verbose?) do
    if verbose? do
      IO.puts("Domo compiles TypeEnsurer modules.")
    end

    case Generator.compile(type_ensurer_paths, verbose?) do
      {:ok, modules, te_warns} -> {:ok, {modules, te_warns}}
      {:error, ex_errors, ex_warnings} -> {:error, {:compile, {ex_errors, ex_warnings}}}
    end
  end

  def ensure_struct_defaults(plan_or_path, verbose?) do
    if verbose? do
      IO.puts("Domo validates structs defaults.")
    end

    ensurable =
      if is_binary(plan_or_path) do
        plan_or_path
      else
        plan_or_path.struct_defaults_to_ensure
      end

    case BatchEnsurer.ensure_struct_defaults(ensurable) do
      :ok -> :ok
      {:error, messages} -> {:error, {:batch_ensurer, messages}}
    end
  end

  def ensure_structs_integrity(plan_path, verbose?) do
    if verbose? do
      IO.puts("Domo validates structs constant values made at compile time.")
    end

    case BatchEnsurer.ensure_struct_integrity(plan_path) do
      :ok -> :ok
      {:error, messages} -> {:error, {:batch_ensurer, messages}}
    end
  end

  def recompile_depending_structs(plan_path, deps_path, preconds_path, verbose?) do
    if verbose? do
      IO.puts("Domo recompiles structs depending on structs with changed types if any. #{plan_path}")
    end

    {:ok, _pid} = ResolvePlanner.ensure_started(plan_path, preconds_path, verbose?: verbose?)

    case DependencyResolver.maybe_recompile_depending_structs(deps_path, preconds_path, verbose?: verbose?) do
      {:ok, _warnings} = ok ->
        ResolvePlanner.ensure_flushed_and_stopped(plan_path)
        ok

      {:noop, []} ->
        ResolvePlanner.stop(plan_path)
        {:ok, []}

      {:error, messages} ->
        ResolvePlanner.stop(plan_path)
        {:error, {:deps, messages}}

      %Error{} = error ->
        ResolvePlanner.stop(plan_path)
        {:error, {:deps, error}}
    end
  end
end
