defmodule Domo.TypeEnsurerFactory.Resolver.Fields.ArgumentsTest do
  use Domo.FileCase, async: true

  alias Domo.TypeEnsurerFactory.Resolver.Fields.Arguments

  describe "all combinations should" do
    test "return 1 element for [[:a], [:b]]" do
      assert [
               [:a, :b]
             ] == Arguments.all_combinations([[:a], [:b]])
    end

    test "return 2 elements for [[:a, :b]]" do
      assert [
               [:a],
               [:b]
             ] == Arguments.all_combinations([[:a, :b]])
    end

    test "return 2 elements for [[:a, :b], [:c]]" do
      assert [
               [:a, :c],
               [:b, :c]
             ] == Arguments.all_combinations([[:a, :b], [:c]])
    end

    test "return 4 elements for [[:a, :b], [:c, :d]]" do
      assert [
               [:a, :c],
               [:a, :d],
               [:b, :c],
               [:b, :d]
             ] == Arguments.all_combinations([[:a, :b], [:c, :d]])
    end

    test "generate a list of all combinations for [[1, 2], [:a, :b], [5.0, 6.1]]" do
      assert [
               [1, :a, 5.0],
               [1, :a, 6.1],
               [1, :b, 5.0],
               [1, :b, 6.1],
               [2, :a, 5.0],
               [2, :a, 6.1],
               [2, :b, 5.0],
               [2, :b, 6.1]
             ] == Arguments.all_combinations([[1, 2], [:a, :b], [5.0, 6.1]])
    end
  end
end
