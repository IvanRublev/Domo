defmodule ExampleAvialia.Cargos.Measurement do
  use Ecto.Schema
  use Domo, skip_defaults: true

  import Ecto.Changeset
  import Domo.Changeset

  @primary_key false
  schema "measurements" do
    field :name, :string, primary_key: true
    field :kilos, :integer

    timestamps()
  end

  @type t :: %__MODULE__{
          name: String.t(),
          kilos: integer()
        }

  def changeset(%__MODULE__{} = item, attrs) do
    item
    |> cast(attrs, typed_fields())
    |> validate_type()
  end
end
