defmodule AppWeb.OrderControllerTest do
  use AppWeb.ConnCase

  import Ecto.Query
  import Routes

  alias App.Repo
  alias App.Repo.DBOrder

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert json_response(conn, 200) =~ "Welcome to Order processor!"
  end

  test "Endpoint accepts urlencoded json that can be sent with curl", %{conn: conn} do
    conn =
      do_post(
        conn,
        :ping,
        "application/x-www-form-urlencoded",
        "%7B%0A%22text%22%3A%0A%22hello%22%0A%7D"
      )

    assert json_response(conn, 200)["text"] =~ "hello"
  end

  test "Endpoint accepts application/json", %{conn: conn} do
    conn = do_post(conn, :ping, "application/json", Jason.encode!(%{"text" => "welcome"}))
    assert json_response(conn, 200)["text"] =~ "welcome"
  end

  test "Endpoint crashes for unsupported content type in request", %{conn: conn} do
    assert_raise Plug.Parsers.UnsupportedMediaTypeError, fn ->
      do_post(conn, :ping, "text/plain", "hello")
    end
  end

  defp do_post(conn, path, content_type, body)
       when is_atom(path) and is_binary(content_type) and is_binary(body) do
    conn
    |> Plug.Conn.put_req_header("content-type", content_type)
    |> post(order_path(conn, path), body)
  end

  defp post_add_order(conn, id: id, note: note, boxes: b) do
    do_post(
      conn,
      :add_order,
      "application/json",
      Jason.encode!(%{
        "id" => id,
        "note" => note,
        "units" => %{"kind" => "boxes", "count" => b}
      })
    )
  end

  defp post_add_order(conn, id: id, kilograms: k) do
    do_post(
      conn,
      :add_order,
      "application/json",
      Jason.encode!(%{"id" => id, "kilograms" => k})
    )
  end

  defp post_add_order(conn, id: id, packages: c) do
    do_post(
      conn,
      :add_order,
      "application/json",
      Jason.encode!(%{
        "id" => id,
        "units" => %{"kind" => "packages", "count" => c}
      })
    )
  end

  test "POST /add_order with quantity in units of boxes and with note persists an Order in Database",
       %{
         conn: conn
       } do
    conn = post_add_order(conn, id: 152, note: "Deliver on Tue", boxes: 5)

    [ord] = Repo.all(from(DBOrder))

    assert json_response(conn, 200)["result"] =~ ":ok"
    assert ord.id == "ord00000152"
    assert ord.quantity == :units
    assert ord.quantity_units == :boxes
    assert ord.quantity_units_count == 5
    assert ord.note == "Deliver on Tue"
  end

  test "POST /add_order with quantity in units of packages persists an Order in Database", %{
    conn: conn
  } do
    conn = post_add_order(conn, id: 2155, packages: 12)

    [ord] = Repo.all(from(DBOrder))

    assert json_response(conn, 200)["result"] =~ ":ok"
    assert ord.id == "ord00002155"
    assert ord.quantity == :units
    assert ord.quantity_units == :packages
    assert ord.quantity_units_count == 12
  end

  test "POST /add_order with quantity in kilograms persists an Order in Database", %{conn: conn} do
    conn = post_add_order(conn, id: 68, kilograms: 1.25)

    [ord] = Repo.all(from(DBOrder))

    assert json_response(conn, 200)["result"] =~ ":ok"
    assert ord.id == "ord00000068"
    assert ord.quantity == :kilos
    assert(ord.quantity_kilos == 1.25)
    assert ord.note == nil
  end

  test "GET /all returns persisted orders", %{conn: conn} do
    conn =
      conn
      |> post_add_order(id: 152, note: "Deliver on Tue", boxes: 5)
      |> recycle()
      |> post_add_order(id: 68, kilograms: 1.25)
      |> recycle()
      |> post_add_order(id: 2155, packages: 12)
      |> recycle()
      |> get(order_path(conn, :all))

    assert json_response(conn, 200) == [
             %{
               "id" => "ord00000152",
               "note" => "Deliver on Tue",
               "units" => %{"kind" => "boxes", "count" => 5}
             },
             %{"id" => "ord00000068", "kilograms" => 1.25},
             %{
               "id" => "ord00002155",
               "units" => %{"kind" => "packages", "count" => 12}
             }
           ]
  end

  test "POST /kilogrammize should reuturn persisted order recalculated into killogramms",
       %{conn: conn} do
    conn =
      conn
      |> post_add_order(id: 152, note: "Deliver on Tue", boxes: 5)
      |> recycle()
      |> post_add_order(id: 68, kilograms: 1.25)
      |> recycle()
      |> post_add_order(id: 2155, packages: 12)
      |> recycle()
      |> do_post(
        :kilogrammize,
        "application/json",
        Jason.encode!(%{"orders" => ["ord00000152", "ord00000068", "ord00002155"]})
      )

    assert json_response(conn, 200) == %{
             "result" => "ok",
             "order_kilograms" => %{
               "ord00000152" => 10.0,
               "ord00000068" => 1.25,
               "ord00002155" => 9.0
             },
             "sum" => 20.25
           }
  end
end
