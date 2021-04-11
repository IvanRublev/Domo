defmodule App.Repo.DBOrder do
  use Ecto.Schema
  use Domo.TaggedTuple

  import Ecto.Changeset
  import EctoEnum

  alias App.Core.Order
  alias App.Core.Order.{Id, Note}
  alias App.Core.Order.Quantity
  alias App.Core.Order.Quantity.{Units, Kilograms}
  alias App.Core.Order.Quantity.Units.{Boxes, Packages}

  defenum(QuantityEnum, :order_quantity, [:units, :kilos])
  defenum(QuantityUnitsEnum, :order_quantity_units, [:unset, :boxes, :packages])

  @primary_key {:id, :string, []}
  schema "orders" do
    field :quantity, QuantityEnum
    field :quantity_units, QuantityUnitsEnum
    field :quantity_units_count, :integer
    field :quantity_kilos, :float
    field :note, :string
    timestamps()
  end

  @spec changeset(map, Order.t()) :: Ecto.Changeset.t()
  def changeset(db_order, %Order{} = order) do
    attrs =
      %{}
      |> Map.put(:id, TaggedTuple.untag!(order.id, Id))
      |> Map.merge(quantity_attrs(order))
      |> Map.merge(note_attrs(order))

    db_order
    |> cast(attrs, [
      :id,
      :quantity,
      :quantity_units,
      :quantity_units_count,
      :quantity_kilos,
      :note
    ])
    |> validate_required([
      :id,
      :quantity,
      :quantity_units,
      :quantity_units_count,
      :quantity_kilos
    ])
  end

  @spec quantity_attrs(Order.t()) :: map
  defp quantity_attrs(%Order{quantity: {Quantity, quantity}}) do
    case quantity do
      Units --- Boxes --- b ->
        %{quantity: :units, quantity_units: :boxes, quantity_units_count: b, quantity_kilos: 0}

      Units --- Packages --- p ->
        %{quantity: :units, quantity_units: :packages, quantity_units_count: p, quantity_kilos: 0}

      Kilograms --- k ->
        %{quantity: :kilos, quantity_units: :unset, quantity_units_count: 0, quantity_kilos: k}
    end
  end

  @spec note_attrs(Order.t()) :: map
  defp note_attrs(%Order{note: Note --- :none}), do: %{note: nil}
  defp note_attrs(%Order{note: Note --- nt}), do: %{note: nt}

  @spec to_order!(%__MODULE__{}) :: Order.t()
  def to_order!(%__MODULE__{id: id} = ord) do
    Order.build!(
      id: Id --- id,
      quantity: quantity_tuple(ord),
      note: note_tuple(ord)
    )
  end

  @spec quantity_tuple(%__MODULE__{}) :: Quantity.t()
  defp quantity_tuple(%__MODULE__{quantity: :units, quantity_units: u, quantity_units_count: c}) do
    Quantity ---
      Units ---
      case u do
        :boxes -> Boxes --- c
        :packages -> Packages --- c
      end
  end

  defp quantity_tuple(%__MODULE__{quantity: :kilos, quantity_kilos: k}) do
    Quantity --- Kilograms --- k
  end

  @spec note_tuple(%__MODULE__{}) :: Note.t()
  defp note_tuple(%__MODULE__{note: nil}), do: Note --- :none
  defp note_tuple(%__MODULE__{note: nt}), do: Note --- nt
end
