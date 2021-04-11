defmodule Domo.TypeEnsurerFactory.Atomizer do
  @moduledoc false

  @keep_bytes_for_atom 64

  @doc false
  def to_atom_maybe_shorten_via_sha256(binary) when byte_size(binary) <= @keep_bytes_for_atom do
    String.to_atom(binary)
  end

  def to_atom_maybe_shorten_via_sha256(binary) do
    binary_head = take_binary_by_graphemes_up_to_byte_size(binary, @keep_bytes_for_atom)

    sha_tail = :crypto.hash(:sha256, binary) |> Base.encode16()

    String.to_atom(binary_head <> "_" <> sha_tail)
  end

  defp take_binary_by_graphemes_up_to_byte_size(binary, target_byte_size) do
    target_byte_size
    |> take_graphemes(binary)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp take_graphemes(_rem_size, _binary, _graphemes \\ [])

  defp take_graphemes(_rem_size, <<>>, graphemes) do
    graphemes
  end

  defp take_graphemes(rem_size, _binary, graphemes) when rem_size <= 0 do
    graphemes
  end

  defp take_graphemes(rem_size, binary, graphemes) do
    {head, tail} = String.next_grapheme(binary)

    head_size = byte_size(head)
    updated_rem_size = rem_size - head_size

    updated_graphemes =
      if updated_rem_size >= 0 do
        [head | graphemes]
      end

    take_graphemes(updated_rem_size, tail, updated_graphemes)
  end
end
