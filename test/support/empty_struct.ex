# credo:disable-for-this-file
defmodule EmptyStruct do
  use Domo

  defstruct []

  @type t :: %__MODULE__{}
end

defmodule EmptyStructIdField do
  use Domo

  defstruct [:id]

  @type t :: %__MODULE__{}
end
