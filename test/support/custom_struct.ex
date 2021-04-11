# credo:disable-for-this-file
defmodule CustomStruct do
  defstruct([:title])
  @type t :: %__MODULE__{title: String.t()}

  def env, do: __ENV__
end
