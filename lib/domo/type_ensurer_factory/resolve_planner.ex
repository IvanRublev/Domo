defmodule Domo.TypeEnsurerFactory.ResolvePlanner do
  @moduledoc false

  use GenServer

  alias Domo.TypeEnsurerFactory.Atomizer

  @spec ensure_started(String.t()) :: {:ok, pid()}
  def ensure_started(plan_path) do
    case start(plan_path) do
      {:ok, _pid} = reply -> reply
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @spec start(String.t()) :: GenServer.on_start()
  def start(plan_path) do
    {map, env} = maybe_read_plan(plan_path, {%{}, %{}})

    GenServer.start(
      __MODULE__,
      {plan_path, map, env},
      name: via(plan_path)
    )
  end

  defp maybe_read_plan(path, default) do
    with {:ok, plan_binary} <- File.read(path),
         {:ok, {_map, _env} = content} <- binary_to_term(plan_binary) do
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

  @spec plan_types_resolving(module, module, atom, Macro.t()) :: :ok | any()
  def plan_types_resolving(plan_path, module, field, type_quoted) do
    GenServer.call(via(plan_path), {:plan, module, field, type_quoted})
  end

  def keep_module_environment(plan_path, module, env) do
    GenServer.call(via(plan_path), {:keep_env, module, env})
  end

  @spec flush(module) :: :ok | {:error, File.posix()}
  def flush(plan_path) do
    GenServer.call(via(plan_path), :flush)
  end

  @spec stop(module) :: :ok
  def stop(plan_path) do
    try do
      GenServer.stop(via(plan_path))
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  @spec ensure_flushed_and_stopped(module) :: :ok | {:error, File.posix()}
  def ensure_flushed_and_stopped(plan_path) do
    try do
      GenServer.call(via(plan_path), :flush_and_stop)
    catch
      :exit, {:noproc, _} -> :ok
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:plan, module, field, type_quoted}, _from, state) do
    {plan_path, map, envs} = state

    case Map.get_and_update(map, module, &add_key(&1, field, type_quoted)) do
      {:ok, map} -> {:reply, :ok, {plan_path, map, envs}}
      {error, _map} -> {:reply, error, state}
    end
  end

  def handle_call({:keep_env, module, env}, _from, state) do
    {plan_path, map, envs} = state

    {:reply, :ok, {plan_path, map, Map.put(envs, module, env)}}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_flush(state), state}
  end

  def handle_call(:flush_and_stop, _from, state) do
    {:stop, :normal, do_flush(state), state}
  end

  defp do_flush(state) do
    {plan_path, map, envs} = state
    File.write(plan_path, :erlang.term_to_binary({map, envs}))
  end

  @spec add_key(nil | map, atom, Macro.t()) :: {:ok, map} | {:error, :field_exists}
  defp add_key(nil, field, type_quoted), do: {:ok, %{field => type_quoted}}

  defp add_key(map, field, type_quoted) do
    Map.get_and_update(map, field, fn
      nil -> {:ok, type_quoted}
      _ -> {{:error, :field_exists}, map}
    end)
  end
end
