defmodule Domo.CodeEvaluation do
  @moduledoc false

  @plan_collection_key __MODULE__.PlanCollection

  def in_mix_compile?(module_env) do
    tracers = Map.get(module_env || %{}, :tracers, [])
    Enum.member?(tracers, Mix.Compilers.ApplicationTracer)
  end

  def in_mix_test?(_module_env) do
    not is_nil(GenServer.whereis(ExUnit.Server))
  end

  def put_plan_collection(flag) do
    Application.put_env(:domo, @plan_collection_key, flag, persistent: true)
  end

  def in_plan_collection? do
    case Application.fetch_env(:domo, @plan_collection_key) do
      {:ok, true} -> true
      _ -> false
    end
  end
end
