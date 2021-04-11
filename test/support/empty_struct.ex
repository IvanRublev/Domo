# credo:disable-for-this-file
defmodule EmptyStruct do
  use Domo

  defstruct []

  @type t :: %__MODULE__{}
end
