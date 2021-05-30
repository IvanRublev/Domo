# credo:disable-for-this-file
defmodule Location do
  @enforce_keys [:country, :city]
  defstruct [:country, :city, :line1, :line2]

  @type t :: %__MODULE__{
          country: String.t(),
          city: String.t(),
          line1: String.t(),
          line2: String.t() | nil
        }
end
