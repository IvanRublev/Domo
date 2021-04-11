defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.Lists do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def list_spec?(type_spec) do
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

  def map_value_type(type_spec, fun) do
    map_value_type(list_kind(type_spec), type_spec, fun)
  end

  defp list_kind(type_spec) do
    case type_spec do
      [_element_spec] -> :proper_list
      [_ | _] -> :keyword_list
      {:nonempty_list, _, [_element_spec]} -> :proper_list
      {improper_kind, _, [_, _]} -> improper_kind
    end
  end

  defp map_value_type(:proper_list, type_spec, fun) do
    case type_spec do
      [element_spec] -> [fun.(element_spec)]
      {:nonempty_list, context, [element_spec]} -> {:nonempty_list, context, [fun.(element_spec)]}
    end
  end

  defp map_value_type(:keyword_list, type_spec, fun) do
    Enum.map(type_spec, fn {key, value} -> {key, fun.(value)} end)
  end

  defp map_value_type(_improper_kind, type_spec, fun) do
    {improper_kind, [], [head_element_spec, tail_element_spec]} = type_spec
    {improper_kind, [], [fun.(head_element_spec), fun.(tail_element_spec)]}
  end

  def match_spec_function_quoted(type_spec) do
    match_list_function_quoted(list_kind(type_spec), type_spec)
  end

  defp match_list_function_quoted(:keyword_list, type_spec) do
    type_spec_str = TypeSpec.to_atom(type_spec)
    {_keys, value_specs} = Enum.unzip(type_spec)

    kv_spec_strings =
      type_spec
      |> Enum.map(fn {key, value_spec} ->
        {key, TypeSpec.to_atom(value_spec)}
      end)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), []), do: :ok

        def do_match_spec(unquote(type_spec_str), [{_key, _value} | _] = list) do
          reduced_list =
            Enum.reduce_while(unquote(kv_spec_strings), list, fn {expected_key, value_spec_atom},
                                                                 list ->
              {list_by_matching_key, filtered_list} =
                Enum.split_with(list, fn {key, _value} -> key == expected_key end)

              value_error =
                Enum.reduce_while(list_by_matching_key, :ok, fn {_key, value}, _acc ->
                  # credo:disable-for-lines:4
                  case do_match_spec(value_spec_atom, value) do
                    :ok -> {:cont, :ok}
                    {:error, _value, _messages} = error -> {:halt, error}
                  end
                end)

              case value_error do
                :ok ->
                  {:cont, filtered_list}

                {:error, value, messages} ->
                  {:halt,
                   {:error, list,
                    [
                      {"The element for the key %{key} has value %{value} that is invalid.",
                       [key: inspect(expected_key), value: inspect(value)]}
                      | messages
                    ]}}
              end
            end)

          if is_list(reduced_list) do
            :ok
          else
            reduced_list
          end
        end
      end

    {match_spec_quoted, value_specs}
  end

  defp match_list_function_quoted(:proper_list, type_spec) do
    {can_be_empty?, element_spec} =
      case type_spec do
        [element_spec] -> {true, element_spec}
        {:nonempty_list, _, [element_spec]} -> {false, element_spec}
      end

    type_spec_str = TypeSpec.to_atom(type_spec)
    element_spec_str = TypeSpec.to_atom(element_spec)

    match_list_elements_quoted =
      match_el_quoted(type_spec_str, element_spec_str, element_spec_str)

    guard_quoted =
      if can_be_empty?, do: quote(do: length(value) >= 0), else: quote(do: length(value) > 0)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), value) when unquote(guard_quoted) do
          case do_match_list_elements(unquote(type_spec_str), value, 0) do
            {:proper, _length} -> :ok
            {:element_error, messages} -> {:error, value, messages}
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [element_spec]}
  end

  defp match_el_quoted(type_spec_str, head_element_spec_str, tail_element_spec_str) do
    quote do
      def do_match_list_elements(unquote(type_spec_str), [head | tail], idx) do
        case do_match_spec(unquote(head_element_spec_str), head) do
          :ok ->
            do_match_list_elements(unquote(type_spec_str), tail, idx + 1)

          {:error, element_value, messages} ->
            {:element_error,
             [
               {"The element at index %{idx} has value %{element_value} that is invalid.",
                [idx: idx, element_value: inspect(element_value)]}
               | messages
             ]}
        end
      end

      def do_match_list_elements(unquote(type_spec_str), [], idx) do
        {:proper, idx}
      end

      def do_match_list_elements(unquote(type_spec_str), tail, idx) do
        case do_match_spec(unquote(tail_element_spec_str), tail) do
          :ok ->
            {:improper, idx}

          {:error, element_value, messages} ->
            {:element_error,
             [
               {"The tail element has value %{element_value} that is invalid.",
                [element_value: inspect(element_value)]}
               | messages
             ]}
        end
      end
    end
  end

  defp match_list_function_quoted(:maybe_improper_list, type_spec) do
    {:maybe_improper_list, [], [head_element_spec, tail_element_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    head_element_spec_str = TypeSpec.to_atom(head_element_spec)
    tail_element_spec_str = TypeSpec.to_atom(tail_element_spec)

    match_list_elements_quoted =
      match_el_quoted(type_spec_str, head_element_spec_str, tail_element_spec_str)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), value) when is_list(value) do
          case do_match_list_elements(unquote(type_spec_str), value, 0) do
            {:element_error, messages} -> {:error, value, messages}
            {_kind, _length} -> :ok
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [head_element_spec, tail_element_spec]}
  end

  defp match_list_function_quoted(:nonempty_improper_list, type_spec) do
    {:nonempty_improper_list, [], [head_element_spec, tail_element_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    head_element_spec_str = TypeSpec.to_atom(head_element_spec)
    tail_element_spec_str = TypeSpec.to_atom(tail_element_spec)

    match_list_elements_quoted =
      match_el_quoted(type_spec_str, head_element_spec_str, tail_element_spec_str)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), value) when is_list(value) do
          case do_match_list_elements(unquote(type_spec_str), value, 0) do
            {:element_error, messages} ->
              {:error, value, messages}

            {_kind, 0} ->
              {:error, value, [{"Expected a nonempty list.", []}]}

            {:proper, _elem_count} ->
              {:error, value, [{"Expected an improper list.", []}]}

            {_kind, _length} ->
              :ok
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [head_element_spec, tail_element_spec]}
  end

  defp match_list_function_quoted(:nonempty_maybe_improper_list, type_spec) do
    {:nonempty_maybe_improper_list, [], [head_element_spec, tail_element_spec]} = type_spec
    type_spec_str = TypeSpec.to_atom(type_spec)
    head_element_spec_str = TypeSpec.to_atom(head_element_spec)
    tail_element_spec_str = TypeSpec.to_atom(tail_element_spec)

    match_list_elements_quoted =
      match_el_quoted(type_spec_str, head_element_spec_str, tail_element_spec_str)

    match_spec_quoted =
      quote do
        def do_match_spec(unquote(type_spec_str), value) when is_list(value) do
          case do_match_list_elements(unquote(type_spec_str), value, 0) do
            {:element_error, messages} ->
              {:error, value, messages}

            {_kind, 0} ->
              {:error, value, [{"Expected a nonempty list.", []}]}

            {_kind, _length} ->
              :ok
          end
        end
      end

    {[match_spec_quoted, match_list_elements_quoted], [head_element_spec, tail_element_spec]}
  end
end
