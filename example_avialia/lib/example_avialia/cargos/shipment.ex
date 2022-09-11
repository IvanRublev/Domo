defmodule ExampleAvialia.Cargos.Shipment do
  use Ecto.Schema
  use Domo, skip_defaults: true

  import Ecto.Changeset
  import Domo.Changeset

  alias Ecto.Changeset
  alias Ecto.Schema
  alias ExampleAvialia.Cargos.ShipmentKind
  alias ExampleAvialia.Cargos.ShipmentWeight
  alias ExampleAvialia.Cargos.ShipmentDocument
  alias ExampleAvialia.SharedKernel

  schema "shipments" do
    field :flight, :string
    field :kind, ShipmentKind
    field :weight, ShipmentWeight
    field :documents_count, :integer
    has_many :documents, ShipmentDocument, on_delete: :delete_all

    timestamps()
  end

  @type t :: %__MODULE__{
          flight: SharedKernel.flight_number(),
          kind: ShipmentKind.value(),
          weight: ShipmentWeight.value(),
          documents_count: non_neg_integer(),
          documents: Schema.has_many(ShipmentDocument.t())
        }
  precond t: &validate_shipment/1

  defp validate_shipment(shipment) do
    cond do
      shipment.documents_count != (real_count = Enum.count(shipment.documents)) ->
        {:error, "Shipment #{shipment.id} expected to have #{shipment.documents_count} associated documents and has #{real_count}."}

      match?({:commercial_cargo, _}, shipment.kind) and not match?({:units, _}, shipment.weight) ->
        {:error, "Commercial shipment must be measured in package units (bags, boxes etc.)"}

      match?({:passenger_baggage, _}, shipment.kind) and not match?({:kilograms, _}, shipment.weight) ->
        {:error, "Baggage shipment must be measured in kilograms"}

      true ->
        :ok
    end
  end

  def changeset(shipment_or_changeset, attrs) do
    shipment_or_changeset
    |> cast(attrs, __schema__(:fields))
    |> cast_assoc(:documents)
    |> validate_type(maybe_filter_precond_errors: true)
    |> maybe_lift_first_error(:documents)
  end

  defp maybe_lift_first_error(changeset, key) do
    if invalid_doc_changeset = Enum.find(changeset.changes[key], &match?(%Changeset{valid?: false}, &1)) do
      doc_error =
        invalid_doc_changeset
        |> Map.get(:errors)
        |> Keyword.values()
        |> List.first()
        |> elem(0)

      Changeset.add_error(changeset, key, doc_error)
    else
      changeset
    end
  end
end
