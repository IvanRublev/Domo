defmodule Domo.TypeEnsurerFactory do
  @moduledoc false

  alias Domo.Raises
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.ResolvePlanner

  defdelegate compile_time?, to: ResolvePlanner
  defdelegate module_name_string(module), to: Alias, as: :atom_to_string
  defdelegate start_resolve_planner(plan_path, preconds_path), to: ResolvePlanner, as: :ensure_started
  defdelegate type_ensurer(module), to: ModuleInspector
  defdelegate has_type_ensurer?(module), to: ModuleInspector
  defdelegate ensure_loaded?(module), to: Code

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

  def collect_types_for_domo_compiler(plan_path, env, bytecode) do
    :ok = ResolvePlanner.keep_module_environment(plan_path, env.module, env)

    {:"::", _, [{:t, _, _}, {:%, _, [_module_name, {:%{}, _, field_type_list}]}]} =
      bytecode
      |> Code.Typespec.fetch_types()
      |> elem(1)
      |> ModuleInspector.filter_direct_types()
      |> Enum.find_value(fn
        {kind, {:t, _, _} = t} when kind in [:type, :opaque] -> t
        _ -> nil
      end)
      |> Code.Typespec.type_to_quoted()

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

  def plan_struct_defaults_ensurance(plan_path, env) do
    global_ensure_struct_defaults = Application.get_env(:domo, :ensure_struct_defaults, true)

    opts = Module.get_attribute(env.module, :domo_options, [])
    ensure_struct_defaults = Keyword.get(opts, :ensure_struct_defaults, global_ensure_struct_defaults)

    if ensure_struct_defaults do
      do_plan_struct_defaults_ensurance(plan_path, env)
    end
  end

  defp do_plan_struct_defaults_ensurance(plan_path, env) do
    struct = Module.get_attribute(env.module, :__struct__) || Module.get_attribute(env.module, :struct)
    # Elixir ignores default values for enforced keys during the construction of the struct anyway
    enforce_keys = Module.get_attribute(env.module, :enforce_keys) || []
    keys_to_drop = [:__struct__ | enforce_keys]

    defaults =
      struct
      |> Map.from_struct()
      |> Enum.reject(fn {key, _value} -> key in keys_to_drop end)
      |> Enum.sort_by(fn {key, _value} -> key end)

    :ok ==
      ResolvePlanner.plan_struct_defaults_ensurance(
        plan_path,
        env.module,
        defaults,
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
      |> Code.Typespec.fetch_types()
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
end
