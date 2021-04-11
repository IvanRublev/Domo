# credo:disable-for-this-file
defmodule CustomStructUsingDomo do
  use Domo

  defstruct([:title])
  @type t :: %__MODULE__{title: String.t() | nil}

  def env, do: __ENV__
end
