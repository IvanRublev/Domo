defmodule Normal.Order do
  use TypedStruct
  use Norm

  typedstruct enforce: true do
    field :id, integer
    field :item, String.t()
    field :quantity, float
  end

  def s,
    do:
      schema(%__MODULE__{
        id: spec(is_integer()),
        item: spec(is_binary()),
        quantity: spec(is_float())
      })

  @contract new!(spec(is_integer()), spec(is_binary()), spec(is_float())) :: s()
  @spec new!(integer, String.t(), float) :: t()
  def new!(id, item, quantity),
    do: struct!(__MODULE__, id: id, item: item, quantity: quantity)
end
