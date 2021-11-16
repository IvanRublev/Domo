defmodule ElixirVersion do
  @moduledoc false

  def version do
    :elixir
    |> Application.spec(:vsn)
    |> to_string()
    |> String.replace(~r/-.*$/, "")
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end
end
