defmodule Domo.TagUntagTest do
  use ExUnit.Case, async: true

  alias Domo.TaggedTuple
  require TaggedTuple
  import TaggedTuple, only: [---: 2]

  defmodule T1, do: nil
  defmodule T2, do: nil
  defmodule T3, do: nil
  defmodule T4, do: nil
  defmodule T5, do: nil
  defmodule T6, do: nil

  test "--- operator should return tagged tuple by joining tag chain of unlimited length with a value" do
    assert T1 --- 2.5 == {T1, 2.5}
    assert T2 --- T1 --- 2.5 == {T2, {T1, 2.5}}
    assert T3 --- T2 --- T1 --- 2.5 == {T3, {T2, {T1, 2.5}}}
  end

  test "--- operator can be used in pattern matching to untag a value" do
    assert outer --- T2 --- inner --- value = {T3, {T2, {T1, 2.5}}}
    assert outer == T3
    assert inner == T1
    assert value == 2.5
  end

  test "tag function should return tagged tuple by joining tag chain of up to 6 tags with a value" do
    assert TaggedTuple.tag(2.5, T1) == {T1, 2.5}
    assert TaggedTuple.tag(2.5, {T2, T1}) == {T2, {T1, 2.5}}
    assert TaggedTuple.tag(2.5, {T3, {T2, T1}}) == {T3, {T2, {T1, 2.5}}}
    assert TaggedTuple.tag(2.5, {T4, {T3, {T2, T1}}}) == {T4, {T3, {T2, {T1, 2.5}}}}
    assert TaggedTuple.tag(2.5, {T5, {T4, {T3, {T2, T1}}}}) == {T5, {T4, {T3, {T2, {T1, 2.5}}}}}

    assert TaggedTuple.tag(2.5, {T6, {T5, {T4, {T3, {T2, T1}}}}}) ==
             {T6, {T5, {T4, {T3, {T2, {T1, 2.5}}}}}}
  end

  describe "untag! function should" do
    test "return value from tagged tuple on tag chain match with up to 6 tags in the chain" do
      assert TaggedTuple.untag!({T1, 2.5}, T1) == 2.5
      assert TaggedTuple.untag!({T2, {T1, 2.5}}, {T2, T1}) == 2.5
      assert TaggedTuple.untag!({T3, {T2, {T1, 2.5}}}, {T3, {T2, T1}}) == 2.5
      assert TaggedTuple.untag!({T4, {T3, {T2, {T1, 2.5}}}}, {T4, {T3, {T2, T1}}}) == 2.5

      assert TaggedTuple.untag!(
               {T5, {T4, {T3, {T2, {T1, 2.5}}}}},
               {T5, {T4, {T3, {T2, T1}}}}
             ) == 2.5

      assert TaggedTuple.untag!(
               {T6, {T5, {T4, {T3, {T2, {T1, 2.5}}}}}},
               {T6, {T5, {T4, {T3, {T2, T1}}}}}
             ) == 2.5
    end

    test "raise ArgumentError if tag chain not matches the tagged tuple" do
      assert_raise ArgumentError,
                   """
                   Tag chain {:foo, :bar} doesn't match one in the tagged tuple \
                   {Domo.TagUntagTest.T2, {Domo.TagUntagTest.T1, 2.5}}.\
                   """,
                   fn ->
                     TaggedTuple.untag!({T2, {T1, 2.5}}, {:foo, :bar})
                   end
    end
  end
end
