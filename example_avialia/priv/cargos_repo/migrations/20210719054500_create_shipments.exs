defmodule ExampleAvialia.CargosRepo.Migrations.CreateShipments do
  use Ecto.Migration

  alias ExampleAvialia.Cargos.ShipmentKind
  alias ExampleAvialia.Cargos.ShipmentWeight

  def change do
    create table(:measurements, primary_key: false) do
      add :name, :string, primary_key: true
      add :kilos, :integer, null: false

      timestamps()
    end

    create table(:shipments) do
      add :kind, ShipmentKind.type(), null: false
      add :flight, :string, null: false
      add :weight, ShipmentWeight.type(), null: false
      add :documents_count, :integer

      timestamps()
    end

    create table(:shipment_documents) do
      add :title, :string, null: false
      add :shipment_id, references(:shipments)

      timestamps()
    end

    create index(:shipment_documents, :shipment_id)
  end
end
