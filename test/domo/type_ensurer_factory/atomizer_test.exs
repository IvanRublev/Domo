defmodule Domo.TypeEnsurerFactory.AtomizerTest do
  use ExUnit.Case, async: true

  alias Domo.TypeEnsurerFactory.Atomizer

  describe "string_to_maybe_md5_atom/1" do
    test "returns atom equivalent to string shorter then 64 bytes" do
      string = String.duplicate("a", 64)
      expected_atom = String.to_atom(string)

      assert Atomizer.to_atom_maybe_shorten_via_sha256(string) == expected_atom
    end

    test """
    returns atom having first 64 bytes from string and sha256 hash as tail \
    for a string longer then 64 bytes\
    """ do
      string = String.duplicate("a", 64) <> "b"
      string_hash = :crypto.hash(:sha256, string) |> Base.encode16()
      expected_atom = String.to_atom(String.duplicate("a", 64) <> "_" <> string_hash)

      assert Atomizer.to_atom_maybe_shorten_via_sha256(string) == expected_atom
    end

    test "returns atom with sha256 tail for string with unicode graphemes of >1 byte size" do
      string = String.duplicate("👩", 16) <> "b"
      string_hash = :crypto.hash(:sha256, string) |> Base.encode16()
      expected_atom = String.to_atom(String.duplicate("👩", 16) <> "_" <> string_hash)

      assert Atomizer.to_atom_maybe_shorten_via_sha256(string) == expected_atom
    end
  end
end
