defmodule App.Core.Order do
  use Domo

  alias App.Core.Order.Quantity

  deftag Id, for_type: String.t()
  deftag Note, for_type: :none | String.t()

  typedstruct do
    field :id, Id.t()
    field :note, Note.t()
    field :quantity, Quantity.t()
  end

  defmacrop assert!(c) do
    quote do
      unless(unquote(c), do: raise(unquote(Macro.to_string(c)) <> " is false."))
    end
  end

  def new!(enumerable) do
    validate!(Enum.into(enumerable, %{}))
    super(enumerable)
  end

  defp validate!(%{id: Id --- id}) do
    assert!(is_binary(id) and id =~ ~r/ord[0-9]{8}/)
  end

  def new_id(id),
    do: Id --- ("ord" <> String.pad_leading(to_string(id), 8, "0"))
end
