defmodule ExampleAvialia.Cargos.ShipmentDocument do
  use Ecto.Schema
  use Domo, ensure_struct_defaults: false

  import Ecto.Changeset
  import Domo.Changeset

  alias ExampleAvialia.Cargos.Shipment

  schema "shipment_documents" do
    belongs_to :shipment, Shipment
    field :title, :string

    timestamps()
  end

  @type t :: %__MODULE__{title: String.t()}
  precond t: &validate_title(&1.title)

  defp validate_title(title) when byte_size(title) > 0, do: :ok
  defp validate_title(_title), do: {:error, "Document's title can't be empty."}

  def changeset(document_or_changeset, attrs) do
    document_or_changeset
    |> cast(attrs, typed_fields())
    |> validate_type()
  end
end
