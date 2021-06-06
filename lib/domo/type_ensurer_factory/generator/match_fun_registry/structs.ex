defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Structs do
  @moduledoc false

  alias Domo.Precondition
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def struct_spec?(type_spec) do
    case type_spec do
      {{:%, _, [{:__aliases__, _, _}, {:%{}, _, _}]}, _precond} -> true
      _ -> false
    end
  end

  def match_spec_function_quoted({type_spec, precond}) do
    if ensurable_struct?(type_spec) do
      delegate_match_spec_to_type_ensurer(type_spec, precond)
    else
      match_spec_in_place(type_spec, precond)
    end
  end

  def ensurable_struct?({:%, _, [struct_alias, _map_spec]} = _type_spec) do
    struct_alias
    |> Alias.alias_to_atom()
    |> ensurable_struct?()
  end

  def ensurable_struct?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :ensure_type_ok, 1)
  end

  def ensurable_struct?(_type_spec) do
    false
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

  defp delegate_match_spec_to_type_ensurer(type_spec, precond) do
    {:%, _, [struct_alias, _map_spec]} = type_spec

    struct_atom = Alias.alias_to_atom(struct_alias)
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, %unquote(struct_atom){} = value, unquote(spec_string_var)) do
          case unquote(struct_atom).ensure_type_ok(value) do
            {:ok, _instance} ->
              unquote(ok_or_precond_call_quoted(precond))

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

  defp match_spec_in_place(type_spec, precond) do
    {:%, _, [_struct_alias, map_spec]} = type_spec

    if map_spec == {:%{}, [], []} do
      match_spec_any_type_fields_function_quoted(type_spec, precond)
    else
      match_spec_exact_type_fields_function_quoted(type_spec, precond)
    end
  end

  defp match_spec_any_type_fields_function_quoted(type_spec, precond) do
    {:%, _, [struct_alias, _map_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    struct_atom = Alias.alias_to_atom(struct_alias)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)
    value_match_var = if precond, do: quote(do: %unquote(struct_atom){} = value), else: quote(do: %unquote(struct_atom){})

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_str), unquote(precond_atom)}, unquote(value_match_var), unquote(spec_string_var)) do
          unquote(ok_or_precond_call_quoted(precond))
        end
      end

    {match_spec_functions_quoted, []}
  end

  defp match_spec_exact_type_fields_function_quoted(type_spec, precond) do
    {:%, _, [struct_alias, map_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    {map_spec_atom, _map_precond_atom, map_spec_string} = TypeSpec.match_spec_attributes({map_spec, nil})

    struct_atom = Alias.alias_to_atom(struct_alias)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_str), unquote(precond_atom)}, %unquote(struct_atom){} = value, unquote(spec_string_var)) do
          case do_match_spec({unquote(map_spec_atom), nil}, Map.from_struct(value), unquote(map_spec_string)) do
            :ok -> unquote(ok_or_precond_call_quoted(precond))
            {:error, _value, _message} = err -> err
          end
        end
      end

    {match_spec_functions_quoted, [{map_spec, nil}]}
  end

  defp ok_or_precond_call_quoted(nil) do
    :ok
  end

  defp ok_or_precond_call_quoted(precond) do
    quote do
      if unquote(Precondition.validation_call_quoted(precond, quote(do: value))) do
        :ok
      else
        message =
          build_error(
            spec_string,
            precond_description: unquote(precond.description),
            precond_type: unquote(Precondition.type_string(precond))
          )

        {:error, value, [message]}
      end
    end
  end
end
