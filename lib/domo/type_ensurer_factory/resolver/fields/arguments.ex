defmodule Domo.TypeEnsurerFactory.Resolver.Fields.Arguments do
  @moduledoc false

  @spec all_combinations(list(list())) :: list(list())
  def all_combinations([]), do: [[]]

  def all_combinations(list_list) do
    hd_list = hd(list_list)

    for hd_el <- hd_list, tail <- all_combinations(list_list -- [hd_list]) do
      [hd_el | tail]
    end
  end
end
