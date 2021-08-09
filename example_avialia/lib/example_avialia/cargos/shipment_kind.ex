defmodule ExampleAvialia.Cargos.ShipmentKind do
  use ExampleAvialia.TaggedTupleEctoType

  alias ExampleAvialia.SharedKernel

  @type value :: {:commercial_cargo, SharedKernel.commercial_shipment_id()} | {:passenger_baggage, SharedKernel.seat_number()}

  def all_variants do
    [:commercial_cargo, :passenger_baggage]
    |> Enum.map(&Atom.to_string/1)
  end

  def build(variant_string, id) do
    variant_atom = String.to_existing_atom(variant_string)
    TaggedTuple.tag(id, variant_atom)
  end

  def get_travel_document_id(shipment_kind) do
    {_tag, document_id} = TaggedTuple.split(shipment_kind)
    document_id
  end
end
