defmodule App.Orders do
  @moduledoc """
  The Orders context.
  """

  import Ecto.Query, warn: false

  alias App.Repo
  alias App.Repo.DBOrder
  alias App.Core.Order

  def create_order(%Order{} = ord) do
    %DBOrder{}
    |> DBOrder.changeset(ord)
    |> Repo.insert()
  end

  def list_orders() do
    DBOrder
    |> Repo.all()
    |> Enum.map(&DBOrder.to_order!/1)
  end

  def list_orders(ids) when is_list(ids) do
    Enum.map(
      Repo.all(from o in DBOrder, where: o.id in ^ids),
      &DBOrder.to_order!/1
    )
  end
end
