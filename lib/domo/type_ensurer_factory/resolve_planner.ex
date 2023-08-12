defmodule Domo.TypeEnsurerFactory.ResolvePlanner do
  @moduledoc false

  use GenServer

  alias Domo.TermSerializer
  alias Domo.TypeEnsurerFactory.Atomizer

  @default_plan %{
    filed_types_to_resolve: %{},
    environments: %{},
    t_reflections: %{},
    structs_to_ensure: [],
    struct_defaults_to_ensure: [],
    remote_types_as_any_by_module: %{}
  }

  def ensure_started(plan_path, preconds_path, opts) do
    {:ok, pid} =
      case start(plan_path, preconds_path, opts) do
        {:ok, _pid} = reply -> reply
        {:error, {:already_started, pid}} -> {:ok, pid}
      end

    # We do this to be able to print debug messages to the :standard_io
    GenServer.call(via(plan_path), {:update_group_leader, Process.group_leader()})

    {:ok, pid}
  end

  def start(plan_path, preconds_path, opts) do
    plan = maybe_read_plan(plan_path, @default_plan)
    preconds = maybe_read_preconds(preconds_path, %{})

    verbose? = Keyword.get(opts, :verbose?, false)

    state = %{
      plan_path: plan_path,
      plan: plan,
      preconds_path: preconds_path,
      preconds: preconds,
      in_memory_types: %{},
      in_memory_dependencies: %{},
      verbose?: verbose?
    }

    GenServer.start_link(__MODULE__, state, name: via(plan_path))
  end

  def started?(plan_path) do
    name = via(plan_path)
    pid = GenServer.whereis(name)
    pid != nil
  end

  defguard is_plan(value)
           when is_map_key(value, :filed_types_to_resolve) and
                  is_map_key(value, :environments) and
                  is_map_key(value, :structs_to_ensure) and
                  is_map_key(value, :struct_defaults_to_ensure) and
                  is_map_key(value, :remote_types_as_any_by_module)

  defp maybe_read_plan(:in_memory, default) do
    default
  end

  defp maybe_read_plan(path, default) do
    with {:ok, plan_binary} <- File.read(path),
         {:ok, content} when is_plan(content) <- binary_to_term(plan_binary) do
      content
    else
      _ -> default
    end
  end

  defp maybe_read_preconds(:in_memory, default) do
    default
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
      {:ok, TermSerializer.binary_to_term(binary)}
    rescue
      _error -> {:error, :malformed_binary}
    end
  end

  def via(:in_memory) do
    __MODULE__
  end

  def via(plan_path) do
    Atomizer.to_atom_maybe_shorten_via_sha256(plan_path)
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

  def keep_struct_t_reflection(plan_path, module, t_reflection) do
    GenServer.call(via(plan_path), {:keep_t_reflection, module, t_reflection})
  end

  def keep_global_remote_types_to_treat_as_any(plan_path, remote_types_as_any) do
    GenServer.call(via(plan_path), {:keep_global_types_as_any, remote_types_as_any})
  end

  def keep_remote_types_to_treat_as_any(plan_path, module, remote_types_as_any) do
    GenServer.call(via(plan_path), {:keep_types_as_any, module, remote_types_as_any})
  end

  def types_treated_as_any(plan_path) do
    GenServer.call(via(plan_path), :types_treated_as_any)
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

  def get_plan_state(plan_path) do
    GenServer.call(via(plan_path), :get_plan_state)
  end

  def clean_plan(:in_memory = plan_path) do
    GenServer.call(via(plan_path), :clean_plan)
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

  def ensure_flushed_and_stopped(plan_path) do
    try do
      GenServer.call(via(plan_path), :flush_and_stop)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  def register_types(:in_memory = path, module, type_list) do
    GenServer.call(via(path), {:register_types, module, type_list})
  end

  def get_types(:in_memory = path, module) do
    GenServer.call(via(path), {:get_types, module})
  end

  def register_many_dependants(:in_memory = path, dependants_on_module) do
    GenServer.call(via(path), {:register_many_dependants, dependants_on_module})
  end

  def get_dependants(:in_memory = path, module) do
    GenServer.call(via(path), {:get_dependants, module})
  end

  @impl true
  def init(%{} = map) do
    if map.verbose? do
      IO.puts("Domo resolve planner started (#{inspect(self())}) #{map.plan_path}.")
    end

    Process.flag(:trap_exit, true)

    {:ok, map}
  end

  @impl true
  def handle_call({:update_group_leader, leader_pid}, _from, state) do
    Process.group_leader(self(), leader_pid)
    {:reply, :ok, state}
  end

  def handle_call({:plan, module, field, type_quoted}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) plans field type #{inspect(module)} #{inspect(field)}.")
    end

    updated_state =
      put_in(
        state,
        [:plan, :filed_types_to_resolve, Access.key(module, %{}), field],
        type_quoted
      )

    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_empty_struct, module}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) plans empty struct #{inspect(module)}.")
    end

    updated_map = Map.put(state.plan.filed_types_to_resolve, module, %{})
    updated_state = put_in(state, [:plan, :filed_types_to_resolve], updated_map)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_env, module, env}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) keeps env #{inspect(module)}.")
    end

    updated_envs = Map.put(state.plan.environments, module, env)
    updated_state = put_in(state, [:plan, :environments], updated_envs)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_t_reflection, module, t_reflection}, _from, state) do
    updated_envs = Map.put(state.plan.t_reflections, module, t_reflection)
    updated_state = put_in(state, [:plan, :t_reflections], updated_envs)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_global_types_as_any, remote_types_as_any}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) keeps global types as any #{inspect(remote_types_as_any)}.")
    end

    updated_remotes_as_any_by_module = map_update_merge(state.plan.remote_types_as_any_by_module, :global, remote_types_as_any)
    updated_state = put_in(state, [:plan, :remote_types_as_any_by_module], updated_remotes_as_any_by_module)
    {:reply, :ok, updated_state}
  end

  def handle_call({:keep_types_as_any, module, remote_types_as_any}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) keeps types as any #{inspect(module)} #{inspect(remote_types_as_any)}.")
    end

    updated_remotes_as_any_by_module = map_update_merge(state.plan.remote_types_as_any_by_module, module, remote_types_as_any)
    updated_state = put_in(state, [:plan, :remote_types_as_any_by_module], updated_remotes_as_any_by_module)
    {:reply, :ok, updated_state}
  end

  def handle_call(:types_treated_as_any, _from, state) do
    types = get_in(state, [:plan, :remote_types_as_any_by_module])
    {:reply, {:ok, types}, state}
  end

  def handle_call({:plan_struct_integrity_ensurance, module, fields, file, line}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) plans struct integrity ensurance #{inspect(module)}.")
    end

    updated_list = state.plan.structs_to_ensure ++ [{module, fields, file, line}]
    updated_state = put_in(state, [:plan, :structs_to_ensure], updated_list)
    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_struct_defaults_ensurance, module, fields, file, line}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) plans defaults ensurance #{inspect(module)} #{inspect(fields)}.")
    end

    updated_list = replace_or_append_defaults(state.plan.struct_defaults_to_ensure, {module, fields, file, line})
    updated_state = put_in(state, [:plan, :struct_defaults_to_ensure], updated_list)
    {:reply, :ok, updated_state}
  end

  def handle_call({:plan_precond_checks, module, types_name_description}, _from, state) do
    if state.verbose? do
      IO.puts("Domo resolve planner (#{inspect(self())}) plans precond checks #{inspect(module)}.")
    end

    updated_precond_map = Map.put(state.preconds, module, types_name_description)
    updated_state = Map.put(state, :preconds, updated_precond_map)

    {:reply, :ok, updated_state}
  end

  def handle_call(:get_plan_state, _from, state) do
    {:reply, {:ok, state.plan, state.preconds}, state}
  end

  def handle_call(:clean_plan, _from, state) do
    updated_state = put_in(state, [:plan], @default_plan)
    {:reply, :ok, updated_state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_flush(state), state}
  end

  def handle_call(:flush_and_stop, _from, state) do
    {:stop, :normal, do_flush(state), state}
  end

  def handle_call({:register_types, module, type_list}, _from, state) do
    updated_state = put_in(state, [:in_memory_types, module], type_list)
    {:reply, :ok, updated_state}
  end

  def handle_call({:get_types, module}, _from, state) do
    reply =
      case Map.get(state.in_memory_types, module) do
        nil -> {:error, :no_types_registered}
        list -> {:ok, list}
      end

    {:reply, reply, state}
  end

  def handle_call({:register_many_dependants, dependants_on_module}, _from, state) do
    updated_state = put_in(state, [:in_memory_dependencies], dependants_on_module)
    {:reply, :ok, updated_state}
  end

  def handle_call({:get_dependants, module}, _from, state) do
    reply =
      case Map.get(state.in_memory_dependencies, module) do
        nil -> {:ok, []}
        list -> {:ok, list}
      end

    {:reply, reply, state}
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

  defp do_flush(%{plan_path: :in_memory}) do
    :ok
  end

  defp do_flush(state) do
    if anything_to_persist?(state) do
      plan_binary = TermSerializer.term_to_binary(state.plan)
      preconds_binary = TermSerializer.term_to_binary(state.preconds)

      with :ok <- File.write(state.plan_path, plan_binary),
           :ok <- File.write(state.preconds_path, preconds_binary) do
        if state.verbose? do
          IO.puts("Domo resolve planner (#{inspect(self())}) flushed plan file.")
        end

        :ok
      else
        {:error, _message} = error ->
          if state.verbose? do
            IO.puts("Domo resolve planner (#{inspect(self())}) failed to write the following error #{inspect(error)}.")
          end

          error
      end
    else
      if state.verbose? do
        IO.puts("Domo resolve planner (#{inspect(self())}) skipped flush to disk because had no data collected.")
      end

      :ok
    end
  end

  defp anything_to_persist?(state) do
    plan = state.plan

    plan.filed_types_to_resolve != %{} or
      plan.environments != %{} or
      plan.t_reflections != %{} or
      plan.structs_to_ensure != [] or
      plan.struct_defaults_to_ensure != [] or
      state.preconds != %{}
  end

  @impl true
  def terminate(reason, state) do
    if state.verbose? do
      try do
        IO.puts("Domo resolve planner (#{inspect(self())}) stopped with reason #{inspect(reason)}.")
      rescue
        _ -> :ok
      end
    end
  end
end
