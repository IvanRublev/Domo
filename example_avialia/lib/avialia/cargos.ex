defmodule Avialia.Cargos do
  @moduledoc """
  The Cargos context.
  """

  use GenServer

  alias Avialia.Cargos.Quantity
  alias Avialia.Cargos.Shipment

  def start_link(_default) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_shipments do
    GenServer.call(__MODULE__, :list_shipments)
  end

  def get_shipment(id) do
    GenServer.call(__MODULE__, {:get_shipment, id})
  end

  def create_shipment(attrs) do
    GenServer.call(__MODULE__, {:create_shipment, attrs})
  end

  def delete_shipment(%Shipment{} = shipment) do
    GenServer.call(__MODULE__, {:delete_shipment, shipment})
  end

  defdelegate to_kilograms(quantity), to: Quantity

  # Server (callbacks)

  @impl true
  def init(_arg) do
    {:ok, []}
  end

  @impl true
  def handle_call(:list_shipments, _from, list) do
    {:reply, Enum.reverse(list), list}
  end

  def handle_call({:get_shipment, id}, _from, list) do
    shipment = Enum.find(list, &(&1.id == id))
    {:reply, shipment, list}
  end

  def handle_call({:create_shipment, attrs}, _from, list) do
    last_id = list |> Enum.at(0, %{}) |> Map.get(:id, 0)
    next_id = last_id + 1
    attrs = put_in(attrs, [:id], next_id)

    case Shipment.new_ok(attrs) do
      {:ok, shipment} = ok ->
        {:reply, ok, [shipment | list]}

      {:error, _message} = error ->
        {:reply, error, list}
    end
  end

  def handle_call({:delete_shipment, shipment}, _from, list) do
    updated_list = List.delete(list, shipment)
    {:reply, shipment, updated_list}
  end
end
