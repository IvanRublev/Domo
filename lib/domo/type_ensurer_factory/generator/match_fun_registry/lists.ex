defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Lists do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def list_spec?(type_spec_precond) do
    {type_spec, _precond} = TypeSpec.split_spec_precond(type_spec_precond)

    case type_spec do
      [{:->, _, [_, _]}] -> false
      {:nonempty_list, _, [_]} -> true
      {:maybe_improper_list, _, [_, _]} -> true
      {:nonempty_improper_list, _, [_, _]} -> true
      {:nonempty_maybe_improper_list, _, [_, _]} -> true
      [_] -> true
      [_ | _] -> true
      _ -> false
    end
  end

  def map_value_type(type_spec_precond, fun) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)
    map_value_type(list_kind(type_spec), type_spec, precond, fun)
  end

  defp list_kind(type_spec) do
    case type_spec do
      [_element_spec] -> :proper_list
      [_ | _] -> :keyword_list
      {:nonempty_list, _, [_element_spec]} -> :proper_list
      {improper_kind, _, [_, _]} -> improper_kind
    end
  end

  defp map_value_type(:proper_list, type_spec, precond, fun) do
    {case type_spec do
       [element_spec] -> [fun.(element_spec)]
       {:nonempty_list, context, [element_spec]} -> {:nonempty_list, context, [fun.(element_spec)]}
     end, precond}
  end

  defp map_value_type(:keyword_list, type_spec, precond, fun) do
    {Enum.map(type_spec, fn {key, value} -> {key, fun.(value)} end), precond}
  end

  defp map_value_type(_improper_kind, type_spec, precond, fun) do
    {improper_kind, [], [head_element_spec, tail_element_spec]} = type_spec
    {{improper_kind, [], [fun.(head_element_spec), fun.(tail_element_spec)]}, precond}
  end

  def match_spec_function_quoted(type_spec_precond) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)
    match_list_function_quoted(list_kind(type_spec), type_spec, precond)
  end

  # credo:disable-for-lines:63
  defp match_list_function_quoted(:keyword_list, type_spec, precond) do
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)

    {_keys, value_spec_preconds} = Enum.unzip(type_spec)

    kv_match_spec_attributes =
      Enum.map(type_spec, fn {key, value_spec_precond} ->
        {key, TypeSpec.match_spec_attributes(value_spec_precond)}
      end)
      |> Macro.escape()

    {value_var, spec_string_var} =
      if precond do
        {quote(do: value), quote(do: spec_string)}
      else
        {quote(do: _value), quote(do: _spec_string)}
      end

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, [] = unquote(value_var), unquote(spec_string_var), _opts),
          do: unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))

        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, [{_key, _value} | _] = value, spec_string, opts) do
          reduced_list =
            Enum.reduce_while(unquote(kv_match_spec_attributes), value, fn {expected_key, value_attributes}, list ->
              {value_spec_atom, value_precond_atom, value_spec_string} = value_attributes
              {list_by_matching_key, filtered_list} = Enum.split_with(list, fn {key, _value} -> key == expected_key end)

              value_error =
                Enum.reduce_while(list_by_matching_key, :ok, fn {_key, value}, _acc ->
                  # credo:disable-for-lines:4
                  case do_match_spec({value_spec_atom, value_precond_atom}, value, value_spec_string, opts) do
                    :ok -> {:cont, :ok}
                    {:error, _value, _messages} = error -> {:halt, error}
                  end
                end)

              case value_error do
                :ok ->
                  {:cont, filtered_list}

                {:error, value, messages} ->
                  message = {
                    "The element for the key %{key} has value %{value} that is invalid.",
                    [key: inspect(expected_key), value: inspect(value)]
                  }

                  {:halt, {:error, list, [message | messages]}}
              end
            end)

          if is_list(reduced_list) do
            unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          else
            reduced_list
          end
        end
      end

    {match_spec_quoted, value_spec_preconds}
  end

  defp match_list_function_quoted(:proper_list, type_spec, precond) do
    {can_be_empty?, element_spec_precond} =
      case type_spec do
        [element_spec_precond] -> {true, element_spec_precond}
        {:nonempty_list, _, [element_spec_precond]} -> {false, element_spec_precond}
      end

    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)

    element_attributes = TypeSpec.match_spec_attributes(element_spec_precond)
    match_list_elements_quoted = match_el_quoted(type_spec_atom, element_attributes, element_attributes)

    guard_quoted = if can_be_empty?, do: quote(do: length(value) >= 0), else: quote(do: length(value) > 0)

    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), opts) when unquote(guard_quoted) do
          case do_match_list_elements(unquote(type_spec_atom), value, 0, opts) do
            {:proper, _length} ->
              unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))

            {:element_error, messages} ->
              {:error, value, messages}
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [element_spec_precond]}
  end

  defp match_list_function_quoted(:maybe_improper_list, type_spec, precond) do
    {:maybe_improper_list, [], [head_spec_precond, tail_spec_precond]} = type_spec
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)

    head_attributes = TypeSpec.match_spec_attributes(head_spec_precond)
    tail_attributes = TypeSpec.match_spec_attributes(tail_spec_precond)
    match_list_elements_quoted = match_el_quoted(type_spec_atom, head_attributes, tail_attributes)

    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), opts) when is_list(value) do
          case do_match_list_elements(unquote(type_spec_atom), value, 0, opts) do
            {:element_error, messages} -> {:error, value, messages}
            {_kind, _length} -> unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [head_spec_precond, tail_spec_precond]}
  end

  defp match_list_function_quoted(:nonempty_improper_list, type_spec, precond) do
    {:nonempty_improper_list, [], [head_spec_precond, tail_spec_precond]} = type_spec
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)

    head_attributes = TypeSpec.match_spec_attributes(head_spec_precond)
    tail_attributes = TypeSpec.match_spec_attributes(tail_spec_precond)
    match_list_elements_quoted = match_el_quoted(type_spec_atom, head_attributes, tail_attributes)

    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), opts) when is_list(value) do
          case do_match_list_elements(unquote(type_spec_atom), value, 0, opts) do
            {:element_error, messages} ->
              {:error, value, messages}

            {_kind, 0} ->
              {:error, value, [{"Expected a nonempty list.", []}]}

            {:proper, _elem_count} ->
              {:error, value, [{"Expected an improper list.", []}]}

            {_kind, _length} ->
              unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [head_spec_precond, tail_spec_precond]}
  end

  defp match_list_function_quoted(:nonempty_maybe_improper_list, type_spec, precond) do
    {:nonempty_maybe_improper_list, [], [head_spec_precond, tail_spec_precond]} = type_spec
    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)

    head_attributes = TypeSpec.match_spec_attributes(head_spec_precond)
    tail_attributes = TypeSpec.match_spec_attributes(tail_spec_precond)
    match_list_elements_quoted = match_el_quoted(type_spec_atom, head_attributes, tail_attributes)

    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), opts) when is_list(value) do
          case do_match_list_elements(unquote(type_spec_atom), value, 0, opts) do
            {:element_error, messages} ->
              {:error, value, messages}

            {_kind, 0} ->
              {:error, value, [{"Expected a nonempty list.", []}]}

            {_kind, _length} ->
              unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [head_spec_precond, tail_spec_precond]}
  end

  defp match_el_quoted(type_spec_atom, head_attributes, tail_attributes) do
    {head_spec_atom, head_precond_atom, head_spec_string} = head_attributes
    {tail_spec_atom, tail_precond_atom, tail_spec_string} = tail_attributes

    quote do
      def do_match_list_elements(unquote(type_spec_atom), [head | tail], idx, opts) do
        case do_match_spec({unquote(head_spec_atom), unquote(head_precond_atom)}, head, unquote(head_spec_string), opts) do
          :ok ->
            do_match_list_elements(unquote(type_spec_atom), tail, idx + 1, opts)

          {:error, element_value, messages} ->
            {:element_error,
             [
               {"The element at index %{idx} has value %{element_value} that is invalid.", [idx: idx, element_value: inspect(element_value)]}
               | messages
             ]}
        end
      end

      def do_match_list_elements(unquote(type_spec_atom), [], idx, _opts) do
        {:proper, idx}
      end

      def do_match_list_elements(unquote(type_spec_atom), tail, idx, opts) do
        case do_match_spec({unquote(tail_spec_atom), unquote(tail_precond_atom)}, tail, unquote(tail_spec_string), opts) do
          :ok ->
            {:improper, idx}

          {:error, element_value, messages} ->
            {:element_error,
             [
               {"The tail element has value %{element_value} that is invalid.", [element_value: inspect(element_value)]}
               | messages
             ]}
        end
      end
    end
  end
end
