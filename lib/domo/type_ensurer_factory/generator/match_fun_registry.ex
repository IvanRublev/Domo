defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.{
    Lists,
    Literals,
    Tuples,
    Maps,
    Structs
  }

  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def stop(pid) do
    GenServer.stop(pid)
  end

  def register_match_spec_fun(pid, type_spec) do
    GenServer.call(pid, {:register, type_spec})
  end

  def list_functions_quoted(pid) do
    GenServer.call(pid, :list_functions_quoted)
  end

  @impl true
  def init(_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, type_spec}, _from, match_funs) do
    {:reply, :ok, put_match_fun_if_missing(match_funs, [type_spec])}
  end

  @impl true
  def handle_call(:list_functions_quoted, _from, match_funs) do
    list =
      match_funs
      |> Enum.flat_map(&unfold_match_fun_list/1)
      |> Enum.sort_by(fn {type_spec_precond_atom, _match_fun} -> type_spec_precond_atom end, &>/2)
      |> Enum.map(fn {_type_spec_atom, match_fun} -> match_fun end)
      |> Enum.uniq()

    {:reply, list, match_funs}
  end

  defp put_match_fun_if_missing(match_funs, []) do
    match_funs
  end

  defp put_match_fun_if_missing(match_funs, [type_spec_precond | rest_type_spec_preconds]) do
    type_spec_precond_atom = TypeSpec.to_atom(type_spec_precond)

    if Map.has_key?(match_funs, type_spec_precond_atom) do
      put_match_fun_if_missing(match_funs, rest_type_spec_preconds)
    else
      {match_fun, underlying_type_spec_preconds} =
        cond do
          Lists.list_spec?(type_spec_precond) -> Lists.match_spec_function_quoted(type_spec_precond)
          Tuples.tuple_spec?(type_spec_precond) -> Tuples.match_spec_function_quoted(type_spec_precond)
          Maps.map_spec?(type_spec_precond) -> Maps.match_spec_function_quoted(type_spec_precond)
          Structs.struct_spec?(type_spec_precond) -> Structs.match_spec_function_quoted(type_spec_precond)
          true -> Literals.match_spec_function_quoted(type_spec_precond)
        end

      put_match_fun_if_missing(
        Map.put(match_funs, type_spec_precond_atom, match_fun),
        underlying_type_spec_preconds ++ rest_type_spec_preconds
      )
    end
  end

  defp unfold_match_fun_list({type_spec_precond_atom, match_fun_list}) when is_list(match_fun_list) do
    {_, match_fun_by_leveled_spec} =
      Enum.reduce(match_fun_list, {0, []}, fn match_fun, {level, list} ->
        {level + 1, [{type_spec_atom_with_level(type_spec_precond_atom, level), match_fun} | list]}
      end)

    Enum.reverse(match_fun_by_leveled_spec)
  end

  defp unfold_match_fun_list(arg), do: List.wrap(arg)

  defp type_spec_atom_with_level(type_spec_precond_atom, level) do
    if level == 0 do
      type_spec_precond_atom
    else
      "»_#{type_spec_precond_atom}_#{level}"
    end
  end
end
