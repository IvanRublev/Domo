defmodule ExampleAvialia.BoardingsRepo.Migrations.CreatePassengers do
  use Ecto.Migration

  def change do
    create table(:passengers) do
      add :flight, :string, null: false
      add :first_name, :string, null: false
      add :last_name, :string, null: false
      add :seat, :string, null: false

      timestamps()
    end
  end
end
