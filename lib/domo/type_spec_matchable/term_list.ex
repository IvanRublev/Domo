defmodule Domo.TypeSpecMatchable.TermList do
  @moduledoc "A module to reduce a list's items matching a given type spec"

  alias Domo.TypeSpecMatchable

  @doc "Returns list of terms excluding those matching the type"
  @spec reject([TypeSpecMatchable.t()], TypeSpecMatchable.t_spec(), TypeSpecMatchable.metadata()) ::
          [TypeSpecMatchable.t()] | []
  def reject(term, {:|, _, [t1, t2]}, metadata),
    do: reject(reject(term, t1, metadata), t2, metadata)

  def reject(term, type, metadata),
    do: Enum.reject(term, &TypeSpecMatchable.match_spec?(&1, type, metadata))
end
