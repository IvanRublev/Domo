defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Maps do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def map_spec?(type_spec) do
    case type_spec do
      {{:%{}, _, [_ | _]}, _precond} -> true
      _ -> false
    end
  end

  def map_key_value_type({{:%{}, _, kv_spec_list} = type_spec, precond}, fun) do
    if Enum.all?(kv_spec_list, fn {key, _value} -> is_atom(key) end) do
      map_key_value_type(:value, type_spec, precond, fun)
    else
      map_key_value_type(:key_value, type_spec, precond, fun)
    end
  end

  defp map_key_value_type(:value, type_spec, precond, fun) do
    {:%{}, context, kv_spec_list} = type_spec
    {{:%{}, context, Enum.map(kv_spec_list, fn {key, value} -> {key, fun.(value)} end)}, precond}
  end

  defp map_key_value_type(:key_value, type_spec, precond, fun) do
    {:%{}, context, kv_spec_list} = type_spec

    updated_kv_spec_list =
      Enum.map(kv_spec_list, fn {{requirement, context, [key_spec]}, value_spec} ->
        {{requirement, context, [fun.(key_spec)]}, fun.(value_spec)}
      end)

    {{:%{}, context, updated_kv_spec_list}, precond}
  end

  def match_spec_function_quoted({{:%{}, _, kv_spec_list} = type_spec, precond}) do
    if Enum.all?(kv_spec_list, fn {key, _value} -> is_atom(key) end) do
      match_spec_atom_keys_quoted(type_spec, precond)
    else
      match_spec_required_keys_quoted(type_spec, precond)
    end
  end

  defp match_spec_atom_keys_quoted(type_spec, precond) do
    {:%{}, _, kv_spec_list} = type_spec

    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)

    {keys, value_spec_preconds} = Enum.unzip(kv_spec_list)

    kvv_quoted =
      keys
      |> Enum.with_index()
      |> Enum.map(fn {key, idx} ->
        {key, Macro.var(String.to_atom("value#{idx}"), __MODULE__)}
      end)

    with_expectations_quoted =
      value_spec_preconds
      |> Enum.zip(kvv_quoted)
      |> Enum.map(fn {value_spec_precond, {key, value_var}} ->
        {value_spec_atom, value_precond_atom, value_spec_string} = TypeSpec.match_spec_attributes(value_spec_precond)

        quote do
          {unquote(key), :ok} <-
            {unquote(key), do_match_spec({unquote(value_spec_atom), unquote(value_precond_atom)}, unquote(value_var), unquote(value_spec_string))}
        end
      end)

    expected_map_size = length(kv_spec_list)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, %{unquote_splicing(kvv_quoted)} = value, unquote(spec_string_var))
            when map_size(value) == unquote(expected_map_size) do
          # credo:disable-for-next-line
          with unquote_splicing(with_expectations_quoted) do
            unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          else
            {map_key, {:error, map_value, messages}} ->
              message = {
                "The field with key %{key} has value %{value} that is invalid.",
                [key: inspect(map_key), value: inspect(map_value)]
              }

              {:error, value, [message | messages]}
          end
        end
      end

    {match_spec_quoted, value_spec_preconds}
  end

  defp match_spec_required_keys_quoted(type_spec, precond) do
    {:%{}, _, kv_spec_list} = type_spec

    rkv_specs =
      Enum.map(kv_spec_list, fn {{requirement, _, [key_spec_precond]}, value_spec_precond} ->
        {value_type_spec, value_precond} = TypeSpec.split_spec_precond(value_spec_precond)
        {key_type_spec, key_precond} = TypeSpec.split_spec_precond(key_spec_precond)
        {requirement, {clear_context(key_type_spec), key_precond}, {clear_context(value_type_spec), value_precond}}
      end)

    key_value_specs =
      Enum.flat_map(rkv_specs, fn {_requirement, key_spec_precond, {value_spec, value_precond}} ->
        [key_spec_precond, quote(do: [{unquote(value_spec), unquote(value_precond)}])]
      end)

    rkvl_spec_atoms =
      rkv_specs
      |> Enum.map(fn {requirement, key_spec_precond, value_spec_precond} ->
        {key_spec_atom, key_precond_atom, key_spec_string} = TypeSpec.match_spec_attributes(key_spec_precond)
        {value_list_spec_atom, value_list_precond_atom, value_list_spec_string} = TypeSpec.match_spec_attributes({[value_spec_precond], nil})
        {requirement, {key_spec_atom, key_precond_atom}, key_spec_string, {value_list_spec_atom, value_list_precond_atom}, value_list_spec_string}
      end)
      |> Macro.escape()

    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, %{} = value, unquote(spec_string_var)) do
          list_value = Map.to_list(value)

          rest_key_values = unquote(filter_list_value_quoted(rkvl_spec_atoms))

          case rest_key_values do
            {:error, _, _} = error ->
              error

            [] ->
              unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))

            list when is_list(list) ->
              message = {"There are extra key value pairs %{kv_pairs} not defined in the type.", [kv_pairs: inspect(list)]}
              {:error, value, [message]}
          end
        end
      end

    {match_spec_quoted, key_value_specs}
  end

  defp clear_context({arg1, arg2, context}) when is_atom(context), do: {arg1, arg2, []}
  defp clear_context(value), do: value

  defp filter_list_value_quoted(rkvl_spec_atoms) do
    quote do
      unquote(rkvl_spec_atoms)
      |> Enum.reduce_while(list_value, fn {requirement, key_spec_precond_atoms, key_spec_string, value_list_spec_precond_atom, value_list_spec_string},
                                          list_value ->
        {list_by_matching_key, filtered_list} =
          Enum.split_with(list_value, fn {key, _value} ->
            match?(:ok, do_match_spec(key_spec_precond_atoms, key, key_spec_string))
          end)

        list_keys_matching_empty? = Enum.empty?(list_by_matching_key)
        required? = requirement == :required

        cond do
          list_keys_matching_empty? and required? ->
            message = {"Expected required key matching %{key_spec} but none was found.", [key_spec: key_spec_string]}
            {:halt, {:error, nil, [message]}}

          list_keys_matching_empty? ->
            {:cont, filtered_list}

          not list_keys_matching_empty? ->
            values_by_matching_key = Enum.map(list_by_matching_key, fn {_key, value} -> value end)

            # credo:disable-for-lines:13
            case do_match_spec(value_list_spec_precond_atom, values_by_matching_key, value_list_spec_string) do
              :ok ->
                {:cont, filtered_list}

              {:error, _values_by_matching_key, messages} ->
                message = {"Invalid value for key matching the %{key_spec} type.", [key_spec: key_spec_string]}
                {:halt, {:error, value, [message | messages]}}
            end
        end
      end)
    end
  end
end
