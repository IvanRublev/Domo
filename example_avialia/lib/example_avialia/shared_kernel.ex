defmodule ExampleAvialia.SharedKernel do
  @moduledoc """
  Shared types and preconditions
  """

  import Domo

  @type flight_number :: String.t()
  precond flight_number: &validate_flight_number/1

  def validate_flight_number(<<"ALA-", _::8*4>>), do: :ok
  def validate_flight_number(_), do: {:error, "Flight number should be of ALA-xxxx format."}

  @type commercial_shipment_id :: String.t()
  precond commercial_shipment_id: &validate_commercial_shipment_id/1

  def validate_commercial_shipment_id(<<"CC-", _, _::binary>>), do: :ok
  def validate_commercial_shipment_id(_), do: {:error, "Commercial shipment id should be of CC-XXX...X format where X is any letter or number."}

  @type seat_number :: String.t()
  precond seat_number: &validate_seat_number/1

  def validate_seat_number(value) do
    if String.match?(value, ~r/\d{1,2}[A-GHJK]{1}/) do
      :ok
    else
      {:error, "Seat number should be of XXY format, where X = 0-9, Y = A-H,I,JK."}
    end
  end
end
