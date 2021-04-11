defmodule Domo.TypeEnsurerFactory.Generator.TypeSpec do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Atomizer

  alias Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.{
    Lists,
    Tuples,
    Maps,
    Structs
  }

  def to_atom(type_spec) do
    type_spec
    |> spec_to_string()
    |> Atomizer.to_atom_maybe_shorten_via_sha256()
  end

  def spec_to_string(type_spec) do
    Macro.to_string(type_spec)
  end

  def generalize_specs_for_ensurable_structs(fields_specs) do
    fields_specs
    |> Enum.map(fn {field, specs} -> {field, maybe_uniq_spec_list(specs)} end)
    |> Enum.into(%{})
  end

  defp maybe_uniq_spec_list(spec_list) do
    spec_list
    |> Enum.map(&maybe_general_struct_spec/1)
    |> Enum.uniq()
  end

  defp maybe_general_struct_spec(type_spec) do
    cond do
      Lists.list_spec?(type_spec) ->
        Lists.map_value_type(type_spec, &maybe_general_struct_spec/1)

      Tuples.tuple_spec?(type_spec) ->
        Tuples.map_value_type(type_spec, &maybe_general_struct_spec/1)

      Maps.map_spec?(type_spec) ->
        Maps.map_key_value_type(type_spec, &maybe_general_struct_spec/1)

      Structs.struct_spec?(type_spec) ->
        if Structs.ensurable_struct?(type_spec) do
          drop_fields_struct_spec(type_spec)
        else
          Structs.map_key_value_type(type_spec, &maybe_general_struct_spec/1)
        end

      true ->
        type_spec
    end
  end

  defp drop_fields_struct_spec({:%, context, [struct_alias, _map_spec]}) do
    {:%, context, [struct_alias, {:%{}, [], []}]}
  end
end
