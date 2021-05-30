defmodule Avialia.Cargos.Quantity do
  import Domo.TaggedTuple

  alias __MODULE__.Units.Boxes
  alias __MODULE__.Units.BigBags
  alias __MODULE__.Units.Barrels

  defmacro alias_units_and_kilograms do
    quote do
      alias unquote(__MODULE__)
      alias unquote(__MODULE__).Units
      alias unquote(__MODULE__).Units.Boxes
      alias unquote(__MODULE__).Units.BigBags
      alias unquote(__MODULE__).Units.Barrels
      alias unquote(__MODULE__).Kilograms
    end
  end

  defmodule Units do
    defmodule Boxes, do: @type(t :: {__MODULE__, pos_integer()})
    defmodule BigBags, do: @type(t :: {__MODULE__, pos_integer()})
    defmodule Barrels, do: @type(t :: {__MODULE__, pos_integer()})

    @type t :: {__MODULE__, Boxes.t() | BigBags.t() | Barrels.t()}
  end

  defmodule Kilograms, do: @type(t :: {__MODULE__, pos_integer()})

  @type t :: {__MODULE__, Units.t() | Kilograms.t()}

  def to_kilograms(__MODULE__ --- Units --- Boxes --- count), do: count * 50
  def to_kilograms(__MODULE__ --- Units --- BigBags --- count), do: count * 25
  def to_kilograms(__MODULE__ --- Units --- Barrels --- count), do: count * 137
  def to_kilograms(__MODULE__ --- Kilograms --- count), do: count
end
