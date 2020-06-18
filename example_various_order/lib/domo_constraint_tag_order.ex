defmodule DomoConstrainsTag.Order do
  use Domo

  deftag Quantity do
    for_type __MODULE__.Kilograms.t() | __MODULE__.Box.t() | __MODULE__.Pallets.t()
    deftag Kilograms, for_type: float
    deftag Box, for_type: :s | :m | :l
    deftag Pallets, for_type: integer
  end

  typedstruct do
    field :id, integer
    field :item, String.t()
    field :quantity, Quantity.t()
  end
end
