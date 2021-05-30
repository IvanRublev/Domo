defmodule Avialia.Boardings do
  @moduledoc """
  The Boardings context.
  """

  use GenServer

  alias Avialia.Boardings.Passenger

  def start_link(_default) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def list_passengers do
    GenServer.call(__MODULE__, :list_passengers)
  end

  def get_passenger(id) do
    GenServer.call(__MODULE__, {:get_passenger, id})
  end

  def create_passenger(attrs) do
    GenServer.call(__MODULE__, {:create_passenger, attrs})
  end

  def delete_passenger(%Passenger{} = passenger) do
    GenServer.call(__MODULE__, {:delete_passenger, passenger})
  end

  # Server (callbacks)

  @impl true
  def init(_arg) do
    {:ok, []}
  end

  @impl true
  def handle_call(:list_passengers, _from, list) do
    {:reply, Enum.reverse(list), list}
  end

  def handle_call({:get_passenger, id}, _from, list) do
    passenger = Enum.find(list, &(&1.id == id))
    {:reply, passenger, list}
  end

  def handle_call({:create_passenger, attrs}, _from, list) do
    last_id = list |> Enum.at(0, %{}) |> Map.get(:id, 0)
    next_id = last_id + 1
    attrs = put_in(attrs, [:id], next_id)

    case Passenger.new_ok(attrs) do
      {:ok, passenger} = ok ->
        {:reply, ok, [passenger | list]}

      {:error, _message} = error ->
        {:reply, error, list}
    end
  end

  def handle_call({:delete_passenger, passenger}, _from, list) do
    updated_list = List.delete(list, passenger)
    {:reply, passenger, updated_list}
  end
end
