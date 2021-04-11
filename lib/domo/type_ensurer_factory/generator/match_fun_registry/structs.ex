defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Structs do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Maps
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def struct_spec?(type_spec) do
    case type_spec do
      {:%, _, [{:__aliases__, _, _}, {:%{}, _, _}]} -> true
      _ -> false
    end
  end

  def match_spec_function_quoted(type_spec) do
    if ensurable_struct?(type_spec) do
      delegate_match_spec_to_type_ensurer(type_spec)
    else
      match_spec_in_place(type_spec)
    end
  end

  def ensurable_struct?({:%, _, [struct_alias, _map_spec]} = _type_spec) do
    module = Alias.alias_to_atom(struct_alias)
    Code.ensure_loaded?(module) and function_exported?(module, :ensure_type_ok, 1)
  end

  def ensurable_struct?(_type_spec) do
    false
  end

  def map_key_value_type(type_spec, fun) do
    if type_spec == {:%{}, [], []} do
      type_spec
    else
      {:%, context, [struct_alias, map_spec]} = type_spec
      updated_map_spec = Maps.map_key_value_type(map_spec, fun)
      {:%, context, [struct_alias, updated_map_spec]}
    end
  end

  defp delegate_match_spec_to_type_ensurer(type_spec) do
    {:%, _, [struct_alias, _map_spec]} = type_spec

    struct_atom = Alias.alias_to_atom(struct_alias)
    type_spec_str = TypeSpec.to_atom(type_spec)

    match_spec_functions_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), %unquote(struct_atom){} = value) do
          case unquote(struct_atom).ensure_type_ok(value) do
            :ok ->
              :ok

            {:error, struct_errors} ->
              messages =
                Enum.map(struct_errors, fn {field, error} ->
                  {"Value of field #{inspect(field)} is invalid due to %{error}", error: error}
                end)

              {:error, value, messages}
          end
        end
      end

    {match_spec_functions_quoted, []}
  end

  defp match_spec_in_place(type_spec) do
    {:%, _, [_struct_alias, map_spec]} = type_spec

    if map_spec == {:%{}, [], []} do
      match_spec_any_type_fields_function_quoted(type_spec)
    else
      match_spec_exact_type_fields_function_quoted(type_spec)
    end
  end

  defp match_spec_any_type_fields_function_quoted(type_spec) do
    {:%, _, [struct_alias, _map_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    struct_atom = Alias.alias_to_atom(struct_alias)

    match_spec_functions_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), %unquote(struct_atom){}), do: :ok
      end

    {match_spec_functions_quoted, []}
  end

  defp match_spec_exact_type_fields_function_quoted(type_spec) do
    {:%, _, [struct_alias, map_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    map_spec_str = TypeSpec.to_atom(map_spec)

    struct_atom = Alias.alias_to_atom(struct_alias)

    match_spec_functions_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), %unquote(struct_atom){} = value) do
          do_match_spec(unquote(map_spec_str), Map.from_struct(value))
        end
      end

    {match_spec_functions_quoted, [map_spec]}
  end
end
