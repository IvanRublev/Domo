defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Maps do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def map_spec?(type_spec) do
    case type_spec do
      {:%{}, _, [_ | _]} -> true
      _ -> false
    end
  end

  def map_key_value_type({:%{}, _, kv_spec_list} = type_spec, fun) do
    if Enum.all?(kv_spec_list, fn {key, _value} -> is_atom(key) end) do
      map_key_value_type(:value, type_spec, fun)
    else
      map_key_value_type(:key_value, type_spec, fun)
    end
  end

  defp map_key_value_type(:value, type_spec, fun) do
    {:%{}, context, kv_spec_list} = type_spec
    {:%{}, context, Enum.map(kv_spec_list, fn {key, value} -> {key, fun.(value)} end)}
  end

  defp map_key_value_type(:key_value, type_spec, fun) do
    {:%{}, context, kv_spec_list} = type_spec

    updated_kv_spec_list =
      Enum.map(kv_spec_list, fn {{requirement, context, [key_spec]}, value_spec} ->
        {{requirement, context, [fun.(key_spec)]}, fun.(value_spec)}
      end)

    {:%{}, context, updated_kv_spec_list}
  end

  def match_spec_function_quoted({:%{}, _, kv_spec_list} = type_spec) do
    if Enum.all?(kv_spec_list, fn {key, _value} -> is_atom(key) end) do
      match_spec_atom_keys_quoted(type_spec)
    else
      match_spec_required_keys_quoted(type_spec)
    end
  end

  defp match_spec_atom_keys_quoted(type_spec) do
    {:%{}, _, kv_spec_list} = type_spec

    type_spec_str = TypeSpec.to_atom(type_spec)
    {keys, value_specs} = Enum.unzip(kv_spec_list)

    kvv_quoted =
      keys
      |> Enum.with_index()
      |> Enum.map(fn {key, idx} ->
        {key, Macro.var(String.to_atom("value#{idx}"), __MODULE__)}
      end)

    with_expectations_quoted =
      value_specs
      |> Enum.zip(kvv_quoted)
      |> Enum.map(fn {value_spec, {key, value_var}} ->
        value_spec_str = TypeSpec.to_atom(value_spec)

        quote do
          {unquote(key), :ok} <-
            {unquote(key), do_match_spec(unquote(value_spec_str), unquote(value_var))}
        end
      end)

    expected_map_size = length(kv_spec_list)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), %{unquote_splicing(kvv_quoted)} = value)
            when map_size(value) == unquote(expected_map_size) do
          # credo:disable-for-next-line
          with unquote_splicing(with_expectations_quoted) do
            :ok
          else
            {map_key, {:error, map_value, messages}} ->
              {:error, value,
               [
                 {"The field with key %{key} has value %{value} that is invalid.",
                  [key: inspect(map_key), value: inspect(map_value)]}
                 | messages
               ]}
          end
        end
      end

    {match_spec_quoted, value_specs}
  end

  defp match_spec_required_keys_quoted(type_spec) do
    {:%{}, _, kv_spec_list} = type_spec

    rkv_specs =
      Enum.map(kv_spec_list, fn {{requirement, _, [key_spec]}, value_spec} ->
        {requirement, clear_context(key_spec), clear_context(value_spec)}
      end)

    key_value_specs =
      Enum.flat_map(rkv_specs, fn {_requirement, key_spec, value_spec} ->
        [key_spec, quote(do: [unquote(value_spec)])]
      end)

    rkvl_spec_atoms =
      rkv_specs
      |> Enum.map(fn {requirement, key_spec, value_spec} ->
        key_spec_str = TypeSpec.to_atom(key_spec)
        value_list_spec_str = TypeSpec.to_atom([value_spec])
        {requirement, key_spec_str, value_list_spec_str}
      end)
      |> Macro.escape()

    type_spec_str = TypeSpec.to_atom(type_spec)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), %{} = value) do
          list_value = Map.to_list(value)

          rest_key_values = unquote(filter_list_value_quoted(rkvl_spec_atoms))

          case rest_key_values do
            {:error, _, _} = error ->
              error

            [] ->
              :ok

            list when is_list(list) ->
              {:error, value,
               [
                 {"There are extra key value pairs %{kv_pairs} not defined in the type.",
                  [kv_pairs: inspect(list)]}
               ]}
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
      |> Enum.reduce_while(list_value, fn {requirement, key_spec_str, value_list_spec_str},
                                          list_value ->
        {list_by_matching_key, filtered_list} =
          Enum.split_with(list_value, fn {key, _value} ->
            match?(:ok, do_match_spec(key_spec_str, key))
          end)

        list_keys_matching_empty? = Enum.empty?(list_by_matching_key)
        required? = requirement == :required

        cond do
          list_keys_matching_empty? and required? ->
            {:halt,
             {:error, nil,
              [
                {"Expected required key matching %{key_spec} but none was found.",
                 [key_spec: key_spec_str]}
              ]}}

          list_keys_matching_empty? ->
            {:cont, filtered_list}

          not list_keys_matching_empty? ->
            values_by_matching_key = Enum.map(list_by_matching_key, fn {_key, value} -> value end)

            # credo:disable-for-lines:13
            case do_match_spec(value_list_spec_str, values_by_matching_key) do
              :ok ->
                {:cont, filtered_list}

              {:error, _values_by_matching_key, messages} ->
                {:halt,
                 {:error, value,
                  [
                    {"Invalid value for key matching the %{key_spec} type.",
                     [key_spec: key_spec_str]}
                    | messages
                  ]}}
            end
        end
      end)
    end
  end
end
