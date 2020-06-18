defmodule App.Core.QuantityConverter do
  use Domo

  alias App.Core.Order
  alias App.Core.Order.Quantity
  alias App.Core.Order.Quantity.Units
  alias App.Core.Order.Quantity.Kilograms, as: OrderKilograms
  alias App.Core.Order.Quantity.Units.{Packages, Boxes}

  deftag Kilograms, for_type: float
  alias __MODULE__.Kilograms, as: ConverterKilograms

  @spec kilogramize(list(Order.t())) ::
          {
            [{Order.t(), ConverterKilograms.t()}],
            ConverterKilograms.t()
          }
  def kilogramize(list) do
    kilo_values =
      list
      |> Enum.map(&to_kilos_value/1)

    total =
      kilo_values
      |> Enum.sum()
      |> tag(ConverterKilograms)

    kilos = Enum.map(kilo_values, &tag(&1, ConverterKilograms))

    {Enum.zip(list, kilos), total}
  end

  @spec to_kilos_value(Order.t()) :: ConverterKilograms.value_t()
  defp to_kilos_value(%Order{quantity: {Quantity, quantity}}) do
    case quantity do
      {Units, {Packages, p}} -> p * 0.75
      {Units, {Boxes, b}} -> b * 2.0
      {OrderKilograms, k} -> k
    end
  end
end
