defmodule Domo.TypeEnsurerFactory.ResolvePlanner do
  @moduledoc false

  use GenServer

  alias Domo.TypeEnsurerFactory.Atomizer

  @compile_time_key_name __MODULE__.CompileTime

  def ensure_started(plan_path, preconds_path) do
    case start(plan_path, preconds_path) do
      {:ok, _pid} = reply -> reply
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  def start(plan_path, preconds_path) do
    default_plan = %{
      filed_types_to_resolve: %{},
      environments: %{},
      structs_to_ensure: [],
      struct_defaults_to_ensure: [],
      remote_types_as_any_by_module: %{}
    }

    plan = maybe_read_plan(plan_path, default_plan)
    preconds = maybe_read_preconds(preconds_path, %{})

    GenServer.start(
      __MODULE__,
      {plan_path, plan, preconds_path, preconds},
      name: via(plan_path)
    )
  end

  defguard is_plan(value)
           when is_map_key(value, :filed_types_to_resolve) and
                  is_map_key(value, :environments) and
                  is_map_key(value, :structs_to_ensure) and
                  is_map_key(value, :struct_defaults_to_ensure) and
                  is_map_key(value, :remote_types_as_any_by_module)

  defp maybe_read_plan(path, default) do
    with {:ok, plan_binary} <- File.read(path),
         {:ok, content} when is_plan(content) <- binary_to_term(plan_binary) do
      content
    else
      _ -> default
    end
  end

  defp maybe_read_preconds(path, default) do
    with {:ok, preconds_binary} <- File.read(path),
         {:ok, content} when is_map(content) <- binary_to_term(preconds_binary) do
      content
    else
      _ -> default
    end
  end

  defp binary_to_term(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _error -> {:error, :malformed_binary}
    end
  end

  def via(plan_path) do
    Atomizer.to_atom_maybe_shorten_via_sha256(plan_path)
  end

  def compile_time? do
    case Application.fetch_env(:domo, @compile_time_key_name) do
      {:ok, true} -> true
      _ -> false
    end
  end

  def plan_types_resolving(plan_path, module, field, type_quoted) do
    GenServer.call(via(plan_path), {:plan, module, field, type_quoted})
  end

  def plan_empty_struct(plan_path, module) do
    GenServer.call(via(plan_path), {:plan_empty_struct, module})
  end

  def keep_module_environment(plan_path, module, env) do
    GenServer.call(via(plan_path), {:keep_env, module, env})
  end

  def keep_global_remote_types_to_treat_as_any(plan_path, remote_types_as_any) do
    GenServer.call(via(plan_path), {:keep_global_types_as_any, remote_types_as_any})
  end

  def keep_remote_types_to_treat_as_any(plan_path, module, remote_types_as_any) do
    GenServer.call(via(plan_path), {:keep_types_as_any, module, remote_types_as_any})
  end

  def plan_struct_integrity_ensurance(plan_path, module, fields, file, line) do
    GenServer.call(via(plan_path), {:plan_struct_integrity_ensurance, module, fields, file, line})
  end

  def plan_struct_defaults_ensurance(plan_path, module, fields, file, line) do
    GenServer.call(via(plan_path), {:plan_struct_defaults_ensurance, module, fields, file, line})
  end

  def plan_precond_checks(plan_path, module, type_name_description) do
    GenServer.call(via(plan_path), {:plan_precond_checks, module, type_name_description})
  end

  def flush(plan_path) do
    GenServer.call(via(plan_path), :flush)
  end

  def stop(plan_path) do
    try do
      GenServer.stop(via(plan_path))
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  def ensure_flushed_and_stopped(plan_path, verbose? \\ false) do
    try do
      GenServer.call(via(plan_path), {:flush_and_stop, verbose?})
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  @impl true
  def init({plan_path, plan, preconds_path, preconds}) do
    Application.put_env(:domo, @compile_time_key_name, true)

    {:ok,
     %{
       plan_path: plan_path,
       plan: plan,
       preconds_path: preconds_path,
       preconds: preconds,
       verbose?: false
     }}
  end

  @impl true
  def handle_call({:plan, module, field, type_quoted}, _from, state) do
    updated_state =
      put_in(
        state,
        [:plan, :filed_types_to_resolve, Access.key(module, %{}), field],
        type_quoted
      )

    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_empty_struct, module}, _from, state) do
    updated_map = Map.put(state.plan.filed_types_to_resolve, module, %{})
    updated_state = put_in(state, [:plan, :filed_types_to_resolve], updated_map)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_env, module, env}, _from, state) do
    updated_envs = Map.put(state.plan.environments, module, env)
    updated_state = put_in(state, [:plan, :environments], updated_envs)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_global_types_as_any, remote_types_as_any}, _from, state) do
    updated_remotes_as_any_by_module = map_update_merge(state.plan.remote_types_as_any_by_module, :global, remote_types_as_any)
    updated_state = put_in(state, [:plan, :remote_types_as_any_by_module], updated_remotes_as_any_by_module)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_types_as_any, module, remote_types_as_any}, _from, state) do
    updated_remotes_as_any_by_module = map_update_merge(state.plan.remote_types_as_any_by_module, module, remote_types_as_any)
    updated_state = put_in(state, [:plan, :remote_types_as_any_by_module], updated_remotes_as_any_by_module)
    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_struct_integrity_ensurance, module, fields, file, line}, _from, state) do
    updated_list = state.plan.structs_to_ensure ++ [{module, fields, file, line}]
    updated_state = put_in(state, [:plan, :structs_to_ensure], updated_list)
    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_struct_defaults_ensurance, module, fields, file, line}, _from, state) do
    updated_list = replace_or_append_defaults(state.plan.struct_defaults_to_ensure, {module, fields, file, line})
    updated_state = put_in(state, [:plan, :struct_defaults_to_ensure], updated_list)
    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_precond_checks, module, types_name_description}, _from, state) do
    updated_precond_map = Map.put(state.preconds, module, types_name_description)
    updated_state = Map.put(state, :preconds, updated_precond_map)

    {:reply, :ok, updated_state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_flush(state), state}
  end

  def handle_call({:flush_and_stop, verbose?}, _from, state) do
    updated_state = %{state | verbose?: verbose?}
    {:stop, :normal, do_flush(updated_state), updated_state}
  end

  defp map_update_merge(map, key, value_list) do
    merge_fn =
      &Map.merge(&1, value_list, fn _key, types_lhs, types_rhs ->
        [types_rhs | types_lhs] |> List.flatten() |> Enum.uniq()
      end)

    Map.update(map, key, value_list, merge_fn)
  end

  defp replace_or_append_defaults(list, defaults) do
    {module, _fields, _file, _line} = defaults
    idx = Enum.find_index(list, fn {existing_module, _fields, _file, _line} -> existing_module == module end)

    if is_nil(idx) do
      Enum.concat(list, [defaults])
    else
      List.replace_at(list, idx, defaults)
    end
  end

  defp do_flush(state) do
    plan_binary = :erlang.term_to_binary(state.plan)
    preconds_binary = :erlang.term_to_binary(state.preconds)

    with :ok <- File.write(state.plan_path, plan_binary),
         :ok <- File.write(state.preconds_path, preconds_binary) do
      if state.verbose? do
        IO.write("""
        Domo resolve planner (#{inspect(self())}) flushed plan file \
        to #{state.plan_path} and preconditions to #{state.preconds_path}.
        """)
      end

      :ok
    else
      {:error, _message} = error ->
        if state.verbose? do
          IO.write("""
          Domo resolve planner (#{inspect(self())}) failed to write \
          to #{state.plan_path} or to #{state.preconds_path} due to \
          the following error #{inspect(error)}.
          """)
        end

        error
    end
  end

  @impl true
  def terminate(reason, state) do
    Application.put_env(:domo, @compile_time_key_name, false)

    if state.verbose? do
      IO.write("""
      Domo resolve planner (#{inspect(self())}) stopped with reason #{inspect(reason)}.
      """)
    end
  end
end
