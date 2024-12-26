defmodule Domo.TypeEnsurerFactory.Precondition do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Atomizer
  alias Domo.TypeEnsurerFactory.Alias

  @enforce_keys [:module, :type_name, :description]
  defstruct @enforce_keys

  def new_escaped(fields), do: Macro.escape(struct!(__MODULE__, fields))

  def unescape(ast) do
    {precondition, _} = Code.eval_quoted(ast)
    precondition
  end

  def to_atom(precondition) do
    precondition
    |> unescape()
    |> type_string()
    |> Atomizer.to_atom_maybe_shorten_via_sha256()
  end

  def type_string(%__MODULE__{} = precondition) do
    module = Alias.atom_to_string(precondition.module)
    type_name = precondition.type_name
    "#{module}.#{type_name}()"
  end

  def ok_or_precond_call_quoted(nil, _spec_string, _value) do
    :ok
  end

  def ok_or_precond_call_quoted(precondition, spec_string, value) do
    precondition = unescape(precondition)

    quote do
      return_value = unquote(precondition.module).__precond__(unquote(precondition.type_name), unquote(value))

      opts = [
        spec_string: unquote(spec_string),
        precond_description: unquote(precondition.description),
        precond_type: unquote(type_string(precondition)),
        value: unquote(value)
      ]

      Domo.PreconditionHandler.cast_to_ok_error(return_value, opts)
    end
  end
end
