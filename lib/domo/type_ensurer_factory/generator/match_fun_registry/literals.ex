defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Literals do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  defguard is_any(type_spec) when type_spec == quote(do: any())

  def match_spec_function_quoted(type_spec) when is_any(type_spec) do
    type_spec_atom = TypeSpec.to_atom(type_spec)

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), nil}, _value, _spec_string, _opts), do: :ok
      end

    {match_spec_functions_quoted, []}
  end

  def match_spec_function_quoted({type_spec, precond}) when is_any(type_spec) do
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), _opts) do
          unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
        end
      end

    {match_spec_functions_quoted, []}
  end

  def match_spec_function_quoted(type_spec_precond) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)
    type_spec_atom = TypeSpec.to_atom(type_spec)
    quoted_guard = guard_quoted(type_spec, :value)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_functions_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), _opts) when unquote(quoted_guard) do
          unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
        end
      end

    {match_spec_functions_quoted, []}
  end

  # credo:disable-for-lines:91
  defp guard_quoted(type_spec, variable_name, context \\ __MODULE__) when is_atom(variable_name) do
    variable_name = Macro.var(variable_name, context)

    case type_spec do
      quote(do: atom()) ->
        quote(do: is_atom(unquote(variable_name)))

      term when is_atom(term) ->
        quote(do: unquote(variable_name) === unquote(term))

      quote(do: %{}) ->
        quote(do: unquote(variable_name) === %{})

      quote(do: map()) ->
        quote(do: is_map(unquote(variable_name)))

      quote(do: pid()) ->
        quote(do: is_pid(unquote(variable_name)))

      quote(do: port()) ->
        quote(do: is_port(unquote(variable_name)))

      quote(do: reference()) ->
        quote(do: is_reference(unquote(variable_name)))

      quote(do: tuple()) ->
        quote(do: is_tuple(unquote(variable_name)))

      quote(do: {}) ->
        quote(do: tuple_size(unquote(variable_name)) == 0)

      quote(do: float()) ->
        quote(do: is_float(unquote(variable_name)))

      quote(do: integer()) ->
        quote(do: is_integer(unquote(variable_name)))

      term when is_integer(term) ->
        quote(do: unquote(variable_name) === unquote(term))

      {:-, _, [term]} when is_integer(term) ->
        quote(do: unquote(variable_name) === -unquote(term))

      {:.., _, [first, last]} ->
        quote(do: unquote(variable_name) in unquote(first)..unquote(last))

      quote(do: neg_integer()) ->
        quote(do: is_integer(unquote(variable_name)) and unquote(variable_name) < 0)

      quote(do: non_neg_integer()) ->
        quote(do: is_integer(unquote(variable_name)) and unquote(variable_name) >= 0)

      quote(do: pos_integer()) ->
        quote(do: is_integer(unquote(variable_name)) and unquote(variable_name) > 0)

      quote(do: <<>>) ->
        quote(do: unquote(variable_name) === <<>>)

      {:<<>>, _, [{:"::", _, [{:_, _, _}, size]}]} when is_integer(size) ->
        quote(do: bit_size(unquote(variable_name)) == unquote(size))

      {:<<>>, _, [{:"::", _, [{:_, _, _}, {:*, _, [{:_, _, _}, chunk_bit_count]}]}]}
      when chunk_bit_count in 1..256 ->
        quote(do: rem(bit_size(unquote(variable_name)), unquote(chunk_bit_count)) == 0)

      {:<<>>, [],
       [
         {:"::", _, [{:_, _, _}, prefix_bit_count]},
         {:"::", _, [{:_, _, _}, {:*, _, [{:_, _, _}, chunk_bit_count]}]}
       ]}
      when is_integer(prefix_bit_count) and prefix_bit_count >= 0 and
             chunk_bit_count in 1..256 >= 0 ->
        quote(
          do:
            rem(
              bit_size(unquote(variable_name)) - unquote(prefix_bit_count),
              unquote(chunk_bit_count)
            ) == 0
        )

      [{:->, _, [_, _]}] ->
        quote(do: is_function(unquote(variable_name)))

      [] ->
        quote(do: length(unquote(variable_name)) == 0)

      {:%, [], [{:__aliases__, _, _} = module_alias, {:%{}, [], []}]} ->
        expected_module_name = Alias.alias_to_atom(module_alias)

        quote(do: :erlang.map_get(:__struct__, unquote(variable_name)) == unquote(expected_module_name))
    end
  end
end
