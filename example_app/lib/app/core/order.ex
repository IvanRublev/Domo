defmodule App.Core.Order do
  use Domo
  use Domo.TaggedTuple
  use TypedStruct

  alias App.Core.Order.Quantity

  defmodule Id, do: @type(t :: {__MODULE__, String.t()})
  defmodule Note, do: @type(t :: {__MODULE__, :none | String.t()})

  typedstruct do
    field :id, Id.t()
    field :note, Note.t()
    field :quantity, Quantity.t()
  end

  def build!(enumerable) do
    validate!(Enum.into(enumerable, %{}))
    new(enumerable)
  end

  defp validate!(%{id: Id --- id}) do
    unless is_binary(id) and id =~ ~r/ord[0-9]{8}/ do
      raise("Id has unsupported format is false.")
    end
  end

  def new_id(id),
    do: Id --- ("ord" <> String.pad_leading(to_string(id), 8, "0"))
end
