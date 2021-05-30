defmodule AvialiaWeb.PageView do
  use AvialiaWeb, :view

  import Domo.TaggedTuple

  alias Avialia.Boardings
  alias Avialia.Cargos
  alias Avialia.Cargos.Quantity

  require Quantity
  Quantity.alias_units_and_kilograms()

  def format_error(message) do
    message
    |> String.split("\n")
    |> Enum.map(&htmlize(&1))
    |> Enum.join()
    |> raw()
  end

  defp htmlize("   - " <> item_text) do
    "<li>#{item_text}</li>"
  end

  defp htmlize(string) do
    "<p>#{string}</p>"
  end

  def render_shipment_kind(:passenger_baggage --- id), do: "Baggage / #{id}"
  def render_shipment_kind(:commercial_cargo --- id), do: "Commercial / #{id}"

  def render_quantity(Quantity --- Units --- Boxes --- count), do: "#{count} Boxes"
  def render_quantity(Quantity --- Units --- BigBags --- count), do: "#{count} Big Bags"
  def render_quantity(Quantity --- Units --- Barrels --- count), do: "#{count} Barrels"
  def render_quantity(Quantity --- Kilograms --- count), do: "#{count}kg"

  def render_kilograms(quantity), do: "#{Cargos.to_kilograms(quantity)}kg"
end
