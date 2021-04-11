defmodule App.Core.Order.Quantity do
  @type t :: {__MODULE__, __MODULE__.Units.t() | __MODULE__.Kilograms.t()}

  defmodule Units do
    @type t :: {__MODULE__, __MODULE__.Packages.t() | __MODULE__.Boxes.t()}

    defmodule Packages, do: @type(t :: {__MODULE__, integer()})
    defmodule Boxes, do: @type(t :: {__MODULE__, integer()})
  end

  defmodule Kilograms, do: @type(t :: {__MODULE__, float()})
end
