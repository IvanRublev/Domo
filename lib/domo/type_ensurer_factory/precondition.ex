defmodule Domo.Precondition do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Atomizer

  @enforce_keys [:module, :type_name, :description]
  defstruct @enforce_keys

  def new(fields), do: struct!(__MODULE__, fields)

  def to_atom(%__MODULE__{} = precondition) do
    precondition
    |> type_string()
    |> Atomizer.to_atom_maybe_shorten_via_sha256()
  end

  def type_string(%__MODULE__{} = precondition) do
    module =
      precondition.module
      |> Module.split()
      |> Enum.reject(&(&1 == "Elixir"))
      |> Enum.join(".")

    "#{module}.#{precondition.type_name}()"
  end

  def validation_call_quoted(%__MODULE__{} = precondition, value) do
    quote do
      unquote(precondition.module).__precond__(unquote(precondition.type_name), unquote(value))
    end
  end
end
