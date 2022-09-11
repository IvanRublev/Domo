defmodule ExampleAvialia.Boardings.Passenger do
  use Ecto.Schema
  use Domo, skip_defaults: true

  import Ecto.Changeset
  import Domo.Changeset

  alias ExampleAvialia.SharedKernel

  schema "passengers" do
    field :flight, :string
    field :first_name, :string
    field :last_name, :string
    field :seat, :string

    timestamps()
  end

  @type t :: %__MODULE__{
          flight: SharedKernel.flight_number(),
          first_name: String.t(),
          last_name: String.t(),
          seat: SharedKernel.seat_number()
        }
  precond t: &do_validate_full_name/1

  defp do_validate_full_name(p) when byte_size(p.first_name) + byte_size(p.last_name) > 30 do
    {:error, "Summary length of the first and the last names should be less or equal to 30 characters."}
  end

  defp do_validate_full_name(_p) do
    :ok
  end

  def changeset(%__MODULE__{} = passenger) do
    change(passenger)
  end

  def changeset(_) do
    change(%__MODULE__{})
  end

  def changeset(passenger_or_changeset, attrs) do
    passenger_or_changeset
    |> cast(attrs, __schema__(:fields))
    |> validate_type()
  end
end
