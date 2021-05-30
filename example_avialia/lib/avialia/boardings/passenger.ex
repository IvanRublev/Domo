defmodule Avialia.Boardings.Passenger do
  @moduledoc """
  The Passenger entity.
  """

  use Domo

  alias Avialia.SharedKernel

  @enforce_keys [:id, :flight, :first_name, :last_name, :seat]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: pos_integer(),
          flight: SharedKernel.flight_number(),
          first_name: String.t(),
          last_name: String.t(),
          seat: SharedKernel.seat_number()
        }
end
