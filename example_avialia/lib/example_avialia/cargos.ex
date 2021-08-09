defmodule ExampleAvialia.Cargos do
  @moduledoc """
  The Cargos context.
  """

  import Ecto.Query, warn: false

  alias ExampleAvialia.CargosRepo
  alias ExampleAvialia.Cargos.Shipment
  alias ExampleAvialia.Cargos.ShipmentKind
  alias ExampleAvialia.Cargos.ShipmentWeight
  alias ExampleAvialia.Cargos.Measurement

  def get_measurements_reference do
    Measurement
    |> CargosRepo.all()
    |> Enum.map(&{&1.name, &1.kilos})
    |> Enum.into(%{})
  end

  def build_shipment_weight(measurement, count) do
    ShipmentWeight.build(measurement, count)
  end

  def get_shipment_kind_variants do
    ShipmentKind.all_variants()
  end

  def build_shipment_kind(variant, id) do
    ShipmentKind.build(variant, id)
  end

  def list_shipment_attributes(measurements_reference) do
    Shipment
    |> CargosRepo.all()
    |> Enum.map(&build_shipment_attributes(&1, measurements_reference))
  end

  defp build_shipment_attributes(shipment, measurements_reference) do
    shipment
    |> Map.from_struct()
    |> Map.drop([:documents])
    |> Map.put(:kind_travel_document_id, ShipmentKind.get_travel_document_id(shipment.kind))
    |> Map.put(:weight_measure, {ShipmentWeight.get_measurement(shipment.weight), ShipmentWeight.get_count(shipment.weight)})
    |> Map.put(:weight_kilos, ShipmentWeight.to_kilograms!(shipment.weight, measurements_reference))
  end

  def get_shipment!(id) do
    Shipment
    |> CargosRepo.get!(id)
    |> CargosRepo.preload(:documents)
    |> Shipment.ensure_type!()
  end

  def create_shipment(fields) do
    %Shipment{}
    |> Shipment.changeset(maybe_set_docs_count(fields))
    |> CargosRepo.insert()
  end

  defp maybe_set_docs_count(%{documents: documents} = fields) do
    Map.put(fields, :documents_count, Enum.count(documents))
  end

  defp maybe_set_docs_count(fields) do
    fields
  end

  def update_shipment(shipment, changes) do
    shipment
    |> Shipment.changeset(maybe_set_docs_count(changes))
    |> CargosRepo.update()
  end

  def delete_shipment(shipment) do
    CargosRepo.delete(shipment)
  end
end
