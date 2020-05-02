defmodule App.Repo.Migrations.AddOrdersTable do
  use Ecto.Migration

  alias App.Repo.DBOrder.{QuantityEnum, QuantityUnitsEnum}

  def change do
    QuantityEnum.create_type()
    QuantityUnitsEnum.create_type()

    create table("orders", primary_key: false) do
      add :id, :string, primary_key: true
      add :quantity, QuantityEnum.type()
      add :quantity_units, QuantityUnitsEnum.type()
      add :quantity_units_count, :integer
      add :quantity_kilos, :float
      add :note, :string
      timestamps()
    end
  end
end
