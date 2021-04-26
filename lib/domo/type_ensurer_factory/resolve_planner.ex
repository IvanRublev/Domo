defmodule Domo.TypeEnsurerFactory.ResolvePlanner do
  @moduledoc false

  use GenServer

  alias Domo.TypeEnsurerFactory.Atomizer

  @compile_time_key_name __MODULE__.CompileTime

  @spec ensure_started(String.t()) :: {:ok, pid()}
  def ensure_started(plan_path) do
    case start(plan_path) do
      {:ok, _pid} = reply -> reply
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @spec start(String.t()) :: GenServer.on_start()
  def start(plan_path) do
    default_plan = %{filed_types_to_resolve: %{}, environments: %{}, structs_to_ensure: []}
    plan = maybe_read_plan(plan_path, default_plan)

    GenServer.start(
      __MODULE__,
      {plan_path, plan},
      name: via(plan_path)
    )
  end

  defguard is_plan(value)
           when is_map_key(value, :filed_types_to_resolve) and
                  is_map_key(value, :environments) and
                  is_map_key(value, :structs_to_ensure)

  defp maybe_read_plan(path, default) do
    with {:ok, plan_binary} <- File.read(path),
         {:ok, content} when is_plan(content) <- binary_to_term(plan_binary) do
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

  @spec via(String.t()) :: atom
  def via(plan_path) do
    Atomizer.to_atom_maybe_shorten_via_sha256(plan_path)
  end

  @spec compile_time?() :: boolean()
  def compile_time? do
    case Application.fetch_env(:domo, @compile_time_key_name) do
      {:ok, true} -> true
      _ -> false
    end
  end

  @spec plan_types_resolving(String.t(), module, atom, Macro.t()) :: :ok | any()
  def plan_types_resolving(plan_path, module, field, type_quoted) do
    GenServer.call(via(plan_path), {:plan, module, field, type_quoted})
  end

  @spec plan_empty_struct(String.t(), module) :: :ok | any()
  def plan_empty_struct(plan_path, module) do
    GenServer.call(via(plan_path), {:plan_empty_struct, module})
  end

  @spec keep_module_environment(String.t(), module, Macro.Env.t()) :: :ok | any()
  def keep_module_environment(plan_path, module, env) do
    GenServer.call(via(plan_path), {:keep_env, module, env})
  end

  @spec plan_struct_integrity_ensurance(String.t(), module, list, String.t(), integer) ::
          :ok | any()
  def plan_struct_integrity_ensurance(plan_path, module, fields, file, line) do
    GenServer.call(via(plan_path), {:plan_struct_ingrity_ensurance, module, fields, file, line})
  end

  @spec flush(String.t()) :: :ok | {:error, File.posix()}
  def flush(plan_path) do
    GenServer.call(via(plan_path), :flush)
  end

  @spec stop(String.t()) :: :ok
  def stop(plan_path) do
    try do
      GenServer.stop(via(plan_path))
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  @spec ensure_flushed_and_stopped(String.t()) :: :ok | {:error, File.posix()}
  def ensure_flushed_and_stopped(plan_path, verbose? \\ false) do
    try do
      GenServer.call(via(plan_path), {:flush_and_stop, verbose?})
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  @impl true
  def init({plan_path, plan}) do
    Application.put_env(:domo, @compile_time_key_name, true)

    {:ok, %{plan_path: plan_path, plan: plan, verbose?: false}}
  end

  @impl true
  def handle_call({:plan, module, field, type_quoted}, _from, state) do
    fields_by_module = state.plan.filed_types_to_resolve

    case Map.get_and_update(fields_by_module, module, &add_key(&1, field, type_quoted)) do
      {:ok, fields_by_module} ->
        updated_state = put_in(state, [:plan, :filed_types_to_resolve], fields_by_module)
        {:reply, :ok, updated_state}

      {error, _map} ->
        {:reply, error, state}
    end
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

  def handle_call({:plan_struct_ingrity_ensurance, module, fields, file, line}, _from, state) do
    updated_list = state.plan.structs_to_ensure ++ [{module, fields, file, line}]
    updated_state = put_in(state, [:plan, :structs_to_ensure], updated_list)
    {:reply, :ok, updated_state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_flush(state), state}
  end

  def handle_call({:flush_and_stop, verbose?}, _from, state) do
    updated_state = %{state | verbose?: verbose?}
    {:stop, :normal, do_flush(updated_state), updated_state}
  end

  @spec add_key(nil | map, atom, Macro.t()) :: {:ok, map} | {:error, :field_exists}
  defp add_key(nil, field, type_quoted), do: {:ok, %{field => type_quoted}}

  defp add_key(map, field, type_quoted) do
    Map.get_and_update(map, field, fn
      nil -> {:ok, type_quoted}
      _ -> {{:error, :field_exists}, map}
    end)
  end

  defp do_flush(state) do
    binary = :erlang.term_to_binary(state.plan)
    result = File.write(state.plan_path, binary)

    if state.verbose? do
      IO.write("""
      Domo resolve planner (#{inspect(self())}) flushed plan file \
      at #{state.plan_path} with #{inspect(result)}.
      """)
    end

    result
  end

  @impl true
  def terminate(reason, state) do
    Application.put_env(:domo, @compile_time_key_name, false)

    if state.verbose? do
      IO.write("""
      Domo resolve planner (#{inspect(self())}) stopped \
      with reason #{inspect(reason)}.\n
      """)
    end
  end
end
