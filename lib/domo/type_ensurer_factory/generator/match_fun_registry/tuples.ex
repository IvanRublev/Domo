defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Tuples do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def tuple_spec?(type_spec_precond) do
    {type_spec, _precond} = TypeSpec.split_spec_precond(type_spec_precond)

    case type_spec do
      {:{}, _, [_element_spec]} -> true
      tuple when tuple_size(tuple) == 2 -> true
      {:{}, _, [_ | _]} -> true
      _ -> false
    end
  end

  def map_value_type(type_spec_precond, fun) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)

    {case type_spec do
       {:{}, context, element_specs} -> {:{}, context, Enum.map(element_specs, &fun.(&1))}
       {elem1, elem2} -> {fun.(elem1), fun.(elem2)}
     end, precond}
  end

  def match_spec_function_quoted(type_spec_precond) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)

    element_spec_preconds =
      case type_spec do
        {:{}, _, element_spec_preconds} -> element_spec_preconds
        {elem1, elem2} -> [elem1, elem2]
      end

    elem_vars_quoted = Enum.map(1..length(element_spec_preconds), &Macro.var(String.to_atom("el#{&1}"), __MODULE__))

    with_expectations_quoted =
      element_spec_preconds
      |> Enum.reduce({[], [], []}, &append_match_spec_attributes_to_lists(&1, &2))
      |> reverse_in_tuple()
      |> Tuple.append(elem_vars_quoted)
      |> Tuple.to_list()
      |> Enum.zip()
      |> Enum.with_index()
      |> Enum.map(fn {{el_spec_atom, el_precond_atom, el_spec_string, var}, idx} ->
        quote do
          {unquote(idx), :ok} <-
            {unquote(idx), do_match_spec({unquote(el_spec_atom), unquote(el_precond_atom)}, unquote(var), unquote(el_spec_string))}
        end
      end)

    else_block_quoted =
      quote do
        {idx, {:error, element_value, messages}} ->
          message = {
            "The element at index %{idx} has value %{element_value} that is invalid.",
            [idx: idx, element_value: inspect(element_value)]
          }

          {:error, value, [message | messages]}
      end

    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, {unquote_splicing(elem_vars_quoted)} = value, unquote(spec_string_var)) do
          # credo:disable-for-next-line
          with unquote_splicing(with_expectations_quoted) do
            unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          else
            unquote(else_block_quoted)
          end
        end
      end

    {match_spec_quoted, element_spec_preconds}
  end

  defp append_match_spec_attributes_to_lists(spec_precond, {spec_atoms, precond_atoms, spec_strings}) do
    {spec_atom, precond_atom, spec_string} = TypeSpec.match_spec_attributes(spec_precond)

    {
      [spec_atom | spec_atoms],
      [precond_atom | precond_atoms],
      [spec_string | spec_strings]
    }
  end

  defp reverse_in_tuple({list1, list2, list3}) do
    {Enum.reverse(list1), Enum.reverse(list2), Enum.reverse(list3)}
  end
end
