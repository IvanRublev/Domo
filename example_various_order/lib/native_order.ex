defmodule Native.Order do
  @enforce_keys [:id, :item, :quantity]
  defstruct([:id, :item, :quantity])

  @type t :: %__MODULE__{id: integer, item: String.t(), quantity: float}

  @spec new!(integer, String.t(), float) :: t()
  def new!(id, item, quantity),
    do: struct!(__MODULE__, id: id, item: item, quantity: quantity)
end
