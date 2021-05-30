defmodule Avialia.Cargos.Shipment do
  @moduledoc """
  The Passenger entity.
  """

  use Domo

  alias Avialia.Cargos.Quantity
  alias Avialia.SharedKernel

  require Quantity
  Quantity.alias_units_and_kilograms()

  @enforce_keys [:id, :kind, :flight, :quantity]
  defstruct @enforce_keys

  @type commercial_shipment_id :: String.t()
  precond commercial_shipment_id: &match?(<<"CC-", _, _::binary>>, &1)

  @type shipment_kind ::
          {:commercial_cargo, commercial_shipment_id()}
          | {:passenger_baggage, SharedKernel.seat_number()}

  @type t :: %__MODULE__{
          id: pos_integer(),
          kind: shipment_kind(),
          flight: SharedKernel.flight_number(),
          quantity: Quantity.t()
        }
  precond t:
            &(case &1.kind do
                {:commercial_cargo, _} ->
                  match?(Quantity --- Units --- _, &1.quantity)

                {:passenger_baggage, _} ->
                  match?(Quantity --- Kilograms --- _, &1.quantity)
              end)
end
