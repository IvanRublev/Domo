defmodule Domo.TermSerializer do
  @moduledoc false

  def term_md5(value) do
    value
    |> term_to_binary()
    |> :erlang.md5()
  end

  def term_to_binary(value) do
    :erlang.term_to_binary(value, minor_version: 1)
  end

  def binary_to_term(binary) do
    # We do this in unsafe way because it works only during the compile time with Domo generated binaries
    :erlang.binary_to_term(binary)
  end
end
