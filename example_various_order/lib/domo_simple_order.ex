defmodule DomoSimple.Order do
  use Domo

  typedstruct do
    field :id, integer
    field :item, String.t()
    field :quantity, float
  end
end
