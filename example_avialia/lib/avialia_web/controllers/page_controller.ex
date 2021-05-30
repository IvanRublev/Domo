defmodule AvialiaWeb.PageController do
  use AvialiaWeb, :controller

  use Domo.TaggedTuple

  alias Avialia.Boardings
  alias Avialia.Cargos
  alias Avialia.Cargos.Quantity

  require Quantity
  Quantity.alias_units_and_kilograms()

  def index(conn, _params) do
    render(conn, "index.html")
  end

  # Boarding service actions

  def new_boarding(conn, params) do
    fields = %{
      first_name: params["passenger"]["first_name"],
      last_name: params["passenger"]["last_name"],
      flight: params["passenger"]["flight_number"],
      seat: params["passenger"]["seat"]
    }

    case Boardings.create_passenger(fields) do
      {:ok, _passenger} -> render(conn, "index.html")
      {:error, message} -> render(conn, "index.html", boarding_errors: message)
    end
  end

  def delete_boarding(conn, params) do
    if id = to_integer(params["id"]) do
      id
      |> Boardings.get_passenger()
      |> Boardings.delete_passenger()
    end

    redirect(conn, to: Routes.page_path(conn, :index))
  end

  # Cargo service actions

  def new_cargo(conn, params) do
    fields = %{
      flight: params["shipment"]["flight_number"],
      kind:
        to_shipment_kind(
          params["shipment"]["shipment_kind"],
          params["shipment"]["shipment_kind_id"]
        ),
      quantity:
        to_quantity(
          params["shipment"]["quantity"],
          params["shipment"]["quantity_count"]
        )
    }

    case Cargos.create_shipment(fields) do
      {:ok, _passenger} -> render(conn, "index.html")
      {:error, message} -> render(conn, "index.html", cargo_errors: message)
    end
  end

  defp to_shipment_kind("baggage", kind_id), do: :passenger_baggage --- kind_id
  defp to_shipment_kind("commercial", kind_id), do: :commercial_cargo --- kind_id
  defp to_shipment_kind(_kind, _kind_id), do: nil

  def to_quantity("boxes", count), do: Quantity --- Units --- Boxes --- to_integer(count)
  def to_quantity("big_bags", count), do: Quantity --- Units --- BigBags --- to_integer(count)
  def to_quantity("barrels", count), do: Quantity --- Units --- Barrels --- to_integer(count)
  def to_quantity("kilograms", count), do: Quantity --- Kilograms --- to_integer(count)

  defp to_integer(string) do
    case Integer.parse(string) do
      {integer, _rest} -> integer
      _ -> nil
    end
  end

  def delete_cargo(conn, params) do
    if id = to_integer(params["id"]) do
      id
      |> Cargos.get_shipment()
      |> Cargos.delete_shipment()
    end

    redirect(conn, to: Routes.page_path(conn, :index))
  end
end
