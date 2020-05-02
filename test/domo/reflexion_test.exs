defmodule Domo.ReflexionTest do
  use ExUnit.Case

  import Domo
  deftag ATag, for_type: integer

  test "tag defined with deftag should return true with __tag__? function" do
    assert ATag.__tag__?() == true
  end

  defmodule ListOfTags do
    use Domo

    deftag Id, for_type: integer
    deftag Note, for_type: String.t()

    defmodule Submodule, do: nil
  end

  describe "module using Domo should" do
    test "return list of defined tags with __tags__ function" do
      assert ListOfTags.__tags__() == [__MODULE__.ListOfTags.Id, __MODULE__.ListOfTags.Note]
    end

    test "return empty list with __tags__ function when no tags are defined" do
      defmodule NoTags do
        use Domo
      end

      assert NoTags.__tags__() == []
    end
  end

  defmodule Subtags do
    deftag Link1 do
      for_type __MODULE__.Link2

      deftag Link2, for_type: integer
    end
  end

  describe "deftag should" do
    test "return list of defined subtags with __tags__function" do
      assert Subtags.Link1.__tags__() == [__MODULE__.Subtags.Link1.Link2]
    end

    test "return empty list with __tags__ when no subtags are defined" do
      assert Subtags.Link1.Link2.__tags__() == []
    end
  end
end
