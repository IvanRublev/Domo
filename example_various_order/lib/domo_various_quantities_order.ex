defmodule DomoVariousQuantities.Order do
  use Domo

  typedstruct do
    field :id, integer
    field :item, String.t()
    field :quantity, {:kilograms | :boxes | :pallets,
                      float | :s | :m | :l | integer}
  end
end
