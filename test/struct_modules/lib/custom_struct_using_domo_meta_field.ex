# credo:disable-for-this-file
defmodule CustomStructUsingDomoMetaField do
  use Domo

  defstruct([:__meta__, :title])
  @type t :: %__MODULE__{title: String.t() | nil}

  def env, do: __ENV__
end
