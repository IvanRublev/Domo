defmodule Domo.TypeSpecMatchable.QuotedType do
  @moduledoc false

  @type t :: {any, any, any}

  @spec get_final_type(t()) :: {:ok, t()} | {:error, {:unknown_typedef_shape, binary}}
  def get_final_type({:"::", _, [_name, quoted_type]}) do
    {:ok, quoted_type}
  end

  def get_final_type(td) do
    {:error, {:unknown_typedef_shape, inspect(td)}}
  end

  @spec is_user_type({atom, any, atom | list}) :: :ok | {:error, any}
  def is_user_type({_name, _, _params} = qt) do
    case type_name_arity(qt) do
      {:error, _} = err ->
        err

      {n, a} ->
        if false == built_in_type?(n, a) do
          :ok
        else
          {:error, :beam_type}
        end
    end
  end

  defp type_name_arity({name, _, params})
       when is_atom(name) and name != :"::" and is_atom(params),
       do: {name, 0}

  defp type_name_arity({name, _, params}) when is_atom(name) and name != :"::",
    do: {name, length(params)}

  defp type_name_arity(_), do: {:error, :unknown_quoted_type_shape}

  # TODO: Remove char_list type by v2.0
  defp built_in_type?(:char_list, 0), do: true
  defp built_in_type?(:charlist, 0), do: true
  defp built_in_type?(:as_boolean, 1), do: true
  defp built_in_type?(:struct, 0), do: true
  defp built_in_type?(:nonempty_charlist, 0), do: true
  defp built_in_type?(:keyword, 0), do: true
  defp built_in_type?(:keyword, 1), do: true
  defp built_in_type?(:var, 0), do: true
  defp built_in_type?(name, arity), do: :erl_internal.is_type(name, arity)
end
