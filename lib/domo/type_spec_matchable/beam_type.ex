defmodule Domo.TypeSpecMatchable.BeamType do
  @moduledoc false

  @type module_types :: [typep: tuple, type: tuple, opaque: tuple]

  @spec expand_type(atom, module_types()) ::
          {:ok, {:type | :remote_type, tuple}} | {:error, any}
  def expand_type(user_type, type_list) do
    case find_type(user_type, type_list) do
      {:ok, {_, {:type, _, _, _}, _} = sys_type} ->
        {:ok, {:type, sys_type}}

      {:ok, {_, {:user_type, _, loc_type_name, _}, _}} ->
        expand_type(loc_type_name, type_list)

      {:ok,
       {_,
        {:remote_type, _,
         [
           {:atom, _, :elixir},
           {:atom, _, :as_boolean},
           [{inner_type_kind, _, _, _} = inner_type]
         ]}, _}} ->
        {:ok, {inner_type_kind, {:t, inner_type, []}}}

      {:ok, {_, {:remote_type, _, _}, _} = another_rem_type} ->
        {:ok, {:remote_type, another_rem_type}}

      {:ok, beam_type} ->
        {:error, {:unknown_beam_type_shape, inspect(beam_type)}}

      err ->
        err
    end
  end

  @spec find_type(atom, module_types()) ::
          {:ok, tuple} | {:error, :notfound}
  def find_type(user_type, type_list) do
    type_list
    |> Keyword.values()
    |> Enum.find_value({:error, :notfound}, &take_spec(user_type, &1))
  end

  @spec take_spec(atom, {atom, tuple}) :: {:ok, tuple} | nil
  defp take_spec(rem_type, {name, _, _} = spec) when rem_type == name, do: {:ok, spec}
  defp take_spec(_, _), do: nil
end
