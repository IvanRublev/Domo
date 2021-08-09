defmodule ExampleAvialia.Boardings do
  @moduledoc """
  The Boardings context.
  """

  import Ecto.Query, warn: false

  alias ExampleAvialia.BoardingsRepo
  alias ExampleAvialia.Boardings.Passenger

  def list_passengers! do
    passengers = BoardingsRepo.all(Passenger)
    Enum.each(passengers, &Passenger.ensure_type!(&1))

    passengers
  end

  def get_passenger!(id) do
    Passenger
    |> BoardingsRepo.get!(id)
    |> Passenger.ensure_type!()
  end

  def passenger_changeset(passenger \\ nil) do
    Passenger.changeset(passenger)
  end

  def create_passenger(fields) do
    passenger_changeset()
    |> Passenger.changeset(fields)
    |> BoardingsRepo.insert()
  end

  def update_passenger(passenger, changes) do
    passenger
    |> Passenger.changeset(changes)
    |> BoardingsRepo.update()
  end

  def delete_passenger(passenger) do
    BoardingsRepo.delete(passenger)
  end
end
