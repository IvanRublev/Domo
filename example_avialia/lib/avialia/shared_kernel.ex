defmodule Avialia.SharedKernel do
  @moduledoc """
  Shared types and preconditions
  """

  import Domo

  @type flight_number :: String.t()
  precond flight_number: &if match?(<<"ALA-", _::8*4>>, &1), do: :ok, else: {:error, "Flight number should be of ALA-xxxx format."}

  @type seat_number :: String.t()
  precond seat_number: &String.match?(&1, ~r/\d{1,2}[A-GHJK]{1}/)
end
