defmodule Domo.TypeEnsurerFactory.Generator.MatchFunRegistry.OrElements do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec

  def or_element_spec?(type_spec_precond) do
    {type_spec, _precond} = TypeSpec.split_spec_precond(type_spec_precond)
    match?({:|, _, [_ | _]}, type_spec)
  end

  def match_spec_function_quoted(type_spec_precond) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)

    {:|, _, elements_spec_precond} = type_spec

    type_spec_atom = TypeSpec.to_atom(type_spec)
    precond_atom = if precond, do: Precondition.to_atom(precond)
    spec_string_var = if precond, do: quote(do: spec_string), else: quote(do: _spec_string)

    [l_elem_spec_precond, r_elem_spec_precond] = elements_spec_precond
    {l_elem_spec_atom, l_elem_precond_atom, l_elem_spec_string} = TypeSpec.match_spec_attributes(l_elem_spec_precond)
    {r_elem_spec_atom, r_elem_precond_atom, r_elem_spec_string} = TypeSpec.match_spec_attributes(r_elem_spec_precond)

    match_spec_quoted =
      quote do
        def do_match_spec({unquote(type_spec_atom), unquote(precond_atom)}, value, unquote(spec_string_var), opts) do
          reply1 = do_match_spec({unquote(l_elem_spec_atom), unquote(l_elem_precond_atom)}, value, unquote(l_elem_spec_string), opts)

          if :ok == reply1 do
            unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))
          else
            reply2 = do_match_spec({unquote(r_elem_spec_atom), unquote(r_elem_precond_atom)}, value, unquote(r_elem_spec_string), opts)

            case reply2 do
              :ok ->
                unquote(Precondition.ok_or_precond_call_quoted(precond, quote(do: spec_string), quote(do: value)))

              {:error, value, _messages} ->
                # find which reply has precondition error and use that one, or no error at all
                {:error, _value, messages1} = reply1
                {:error, _value, messages2} = reply2

                # we join all errors together
                messages = messages1 ++ messages2

                # we add nil to the error list to make the error builder function to form
                # a general message about mismatching | sum type
                {:error, value, [nil | messages]}
            end
          end
        end
      end

    {[match_spec_quoted], elements_spec_precond}
  end

  def map_value_type(type_spec_precond, fun) do
    {type_spec, precond} = TypeSpec.split_spec_precond(type_spec_precond)

    {:|, _, elements_spec_precond} = type_spec

    elements_spec_precond =
      Enum.map(elements_spec_precond, fn case_spec_precond ->
        fun.(case_spec_precond)
      end)

    {{:|, [], elements_spec_precond}, precond}
  end
end
