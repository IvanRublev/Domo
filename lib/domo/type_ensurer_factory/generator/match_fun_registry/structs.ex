defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Structs do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def struct_spec?(type_spec) do
    case type_spec do
      {{:%, _, [{:__aliases__, _, _}, {:%{}, _, _}]}, _precond} -> true
      {{:%, _, [struct_name, {:%{}, _, _}]}, _precond} when is_atom(struct_name) -> true
      _ -> false
    end
  end

  def match_spec_function_quoted({type_spec, precond}) do
    {:%, _, [struct_alias, _map_spec]} = type_spec

    struct_atom = Alias.alias_to_atom(struct_alias)
    type_ensurer = ModuleInspector.type_ensurer(struct_atom)
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, %unquote(struct_atom){} = value, unquote(spec_string_var)) do
          case Domo._validate_fields_ok(unquote(type_ensurer), value, []) do
            {:ok, _instance} ->
              unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))

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

  def map_key_value_type({type_spec, precond}, fun) do
    if type_spec == {:%{}, [], []} do
      {type_spec, precond}
    else
      {:%, context, [struct_alias, map_spec]} = type_spec

      {:%{}, map_context, kv_spec_list} = map_spec
      updated_map_spec = {:%{}, map_context, Enum.map(kv_spec_list, fn {key, value} -> {key, fun.(value)} end)}

      {{:%, context, [struct_alias, updated_map_spec]}, precond}
    end
  end
end
