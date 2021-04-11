defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Tuples do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def tuple_spec?(type_spec) do
    case type_spec do
      {:{}, _, [_element_spec]} -> true
      tuple when tuple_size(tuple) == 2 -> true
      {:{}, _, [_ | _]} -> true
      _ -> false
    end
  end

  def map_value_type(type_spec, fun) do
    case type_spec do
      {:{}, context, element_specs} -> {:{}, context, Enum.map(element_specs, &fun.(&1))}
      {elem1, elem2} -> {fun.(elem1), fun.(elem2)}
    end
  end

  def match_spec_function_quoted(type_spec) do
    element_specs =
      case type_spec do
        {:{}, _, element_specs} -> element_specs
        {elem1, elem2} -> [elem1, elem2]
      end

    elem_vars_quoted =
      Enum.map(1..length(element_specs), &Macro.var(String.to_atom("el#{&1}"), __MODULE__))

    with_expectations_quoted =
      element_specs
      |> Enum.map(&TypeSpec.to_atom/1)
      |> Enum.zip(elem_vars_quoted)
      |> Enum.with_index()
      |> Enum.map(fn {{element_spec_atom, var}, idx} ->
        quote do
          {unquote(idx), :ok} <-
            {unquote(idx), do_match_spec(unquote(element_spec_atom), unquote(var))}
        end
      end)

    type_spec_str = TypeSpec.to_atom(type_spec)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), {unquote_splicing(elem_vars_quoted)} = value) do
          # credo:disable-for-next-line
          with unquote_splicing(with_expectations_quoted) do
            :ok
          else
            {idx, {:error, element_value, messages}} ->
              {:error, value,
               [
                 {"The element at index %{idx} has value %{element_value} that is invalid.",
                  [idx: idx, element_value: inspect(element_value)]}
                 | messages
               ]}
          end
        end
      end

    {match_spec_quoted, element_specs}
  end
end
