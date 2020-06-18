defmodule DomoConstrains.Order do
  use Domo

  defmodule Quantity do
    @type t :: {Quantity, __MODULE__.Kilograms.t() | __MODULE__.Box.t() | __MODULE__.Pallets.t()}
    defmodule Kilograms, do: @type t :: {__MODULE__, float}
    defmodule Box, do: @type t :: {__MODULE__, :s | :m | :l}
    defmodule Pallets, do: @type t :: {__MODULE__, integer}
  end

  typedstruct do
    field :id, integer
    field :item, String.t()
    field :quantity, Quantity.t()
  end
end
