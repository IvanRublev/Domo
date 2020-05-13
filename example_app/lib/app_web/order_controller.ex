defmodule AppWeb.OrderController do
  use AppWeb, :controller
  use Domo

  alias App.Core.Order
  alias App.Core.Order.{Id, Note}
  alias App.Core.Order.Quantity
  alias App.Core.Order.Quantity.{Units, Kilograms}
  alias App.Core.Order.Quantity.Units.{Boxes, Packages}

  alias App.Orders
  alias App.Core.QuantityConverter
  alias App.Core.QuantityConverter.Kilograms, as: ConverterKilograms

  # --- index ------------------------------
  def index(conn, _params) do
    json(conn, "Welcome to Order processor! See README.MD for usage examples.")
  end

  # --- ping -------------------------------
  def ping(conn, params) do
    json(conn, params)
  end

  # --- add order ---------------------------
  def add_order(conn, %{"id" => id, "units" => units} = params) do
    ord =
      Order.new!(
        id: Order.new_id(id),
        quantity: Quantity --- Units --- units_from_map(units),
        note: note(params["note"])
      )

    json(conn, %{"result" => inspect(Orders.create_order(ord))})
  end

  def add_order(conn, %{"id" => id, "kilograms" => kilos} = params) when is_float(kilos) do
    ord =
      Order.new!(
        id: Order.new_id(id),
        quantity: Quantity --- Kilograms --- kilos,
        note: note(params["note"])
      )

    json(conn, %{"result" => inspect(Orders.create_order(ord))})
  end

  defp units_from_map(%{"kind" => k, "count" => c}) do
    case k do
      "boxes" -> Boxes --- c
      "packages" -> Packages --- c
    end
  end

  defp note(nt) when is_binary(nt), do: Note --- nt
  defp note(_), do: Note --- :none

  # --- all orders ---------------------------
  def all(conn, _params) do
    json(conn, Enum.map(Orders.list_orders(), &map_from_order/1))
  end

  defp map_from_order(%Order{id: Id --- id} = ord) do
    %{"id" => id}
    |> Map.merge(map_from_note(ord.note))
    |> Map.merge(map_from_quantity(ord.quantity))
  end

  defp map_from_note(Note --- :none), do: %{}
  defp map_from_note(Note --- nt), do: %{"note" => nt}

  defp map_from_quantity(Quantity --- Kilograms --- k), do: %{"kilograms" => k}
  defp map_from_quantity(Quantity --- Units --- units), do: %{"units" => map_from_units(units)}

  defp map_from_units(Boxes --- c), do: %{"kind" => "boxes", "count" => c}
  defp map_from_units(Packages --- c), do: %{"kind" => "packages", "count" => c}

  # --- kilogrammize ---------------------------
  def kilogrammize(conn, %{"orders" => ids}) do
    {ord_kilo, sum} =
      ids
      |> Orders.list_orders()
      |> QuantityConverter.kilogramize()

    resp =
      %{"result" => "ok"}
      |> Map.merge(%{"order_kilograms" => map_from_ord_kilo(ord_kilo)})
      |> Map.put("sum", untag!(sum, ConverterKilograms))

    json(conn, resp)
  end

  defp map_from_ord_kilo(ord_kilo) do
    ord_kilo
    |> Enum.reduce(%{}, fn {%Order{id: Id --- id}, ConverterKilograms --- kilo}, mp ->
      Map.put(mp, id, kilo)
    end)
  end
end
