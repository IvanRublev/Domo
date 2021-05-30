defmodule Domo.TypeEnsurerFactory.Generator.TypeSpec do
  @moduledoc false

  alias Domo.Precondition
  alias Domo.TypeEnsurerFactory.Atomizer

  alias Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.{
    Lists,
    Tuples,
    Maps,
    Structs
  }

  def match_spec_attributes(type_spec_precond) do
    {type_spec, type_precond} = split_spec_precond(type_spec_precond)
    type_spec_atom = to_atom(type_spec)
    type_precond_atom = if type_precond, do: Precondition.to_atom(type_precond)
    type_spec_string = type_spec_precond |> filter_preconds() |> spec_to_string()

    {type_spec_atom, type_precond_atom, type_spec_string}
  end

  def split_spec_precond({_type_spec, _precond} = value) do
    value
  end

  def split_spec_precond(type_spec) do
    {type_spec, nil}
  end

  def to_atom(type_spec) do
    type_spec
    |> spec_to_string()
    |> Atomizer.to_atom_maybe_shorten_via_sha256()
  end

  def spec_to_string(type_spec) do
    Macro.to_string(type_spec)
  end

  def generalize_specs_for_ensurable_structs(fields_specs_t_precond) do
    {specs, t_precond} = fields_specs_t_precond

    updated_specs =
      for {field, specs} <- specs, into: %{} do
        {field, maybe_uniq_spec_list(specs)}
      end

    {updated_specs, t_precond}
  end

  defp maybe_uniq_spec_list(spec_list) do
    spec_list
    |> Enum.map(&maybe_general_struct_spec/1)
    |> Enum.uniq()
  end

  defp maybe_general_struct_spec(type_spec_precond) do
    cond do
      Lists.list_spec?(type_spec_precond) ->
        Lists.map_value_type(type_spec_precond, &maybe_general_struct_spec/1)

      Tuples.tuple_spec?(type_spec_precond) ->
        Tuples.map_value_type(type_spec_precond, &maybe_general_struct_spec/1)

      Maps.map_spec?(type_spec_precond) ->
        Maps.map_key_value_type(type_spec_precond, &maybe_general_struct_spec/1)

      Structs.struct_spec?(type_spec_precond) ->
        {type_spec, _precond} = split_spec_precond(type_spec_precond)

        if Structs.ensurable_struct?(type_spec) do
          drop_fields_struct_spec(type_spec_precond)
        else
          Structs.map_key_value_type(type_spec_precond, &maybe_general_struct_spec/1)
        end

      true ->
        type_spec_precond
    end
  end

  defp drop_fields_struct_spec({{:%, context, [struct_alias, _map_spec]}, precond}) do
    {{:%, context, [struct_alias, {:%{}, [], []}]}, precond}
  end

  def filter_preconds(type_spec_precond) do
    result =
      cond do
        Lists.list_spec?(type_spec_precond) ->
          Lists.map_value_type(type_spec_precond, &filter_preconds/1)

        Tuples.tuple_spec?(type_spec_precond) ->
          Tuples.map_value_type(type_spec_precond, &filter_preconds/1)

        Maps.map_spec?(type_spec_precond) ->
          Maps.map_key_value_type(type_spec_precond, &filter_preconds/1)

        Structs.struct_spec?(type_spec_precond) ->
          Structs.map_key_value_type(type_spec_precond, &filter_preconds/1)

        true ->
          {spec, _precond} = split_spec_precond(type_spec_precond)
          spec
      end

    {spec, _precond} = split_spec_precond(result)
    spec
  end
end
