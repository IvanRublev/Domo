defmodule DomoTest do
  use ExUnit.Case

  doctest Domo

  def types(bytecode) do
    bytecode
    |> Code.Typespec.fetch_types()
    |> elem(1)
    |> Enum.sort()
  end

  describe "deftag should define a module with type t of a tagged tuple, and value_t of value" do
    def match_t_value_t(module, types) do
      [
        type: {:t, {:type, _, :tuple, [{:atom, _, ^module}, {:type, _, :float, []}]}, []},
        type: {:value_t, {:type, _, :float, []}, []}
      ] = types
    end

    test "in oneline form" do
      {:module, _, bytecode, _} = Domo.deftag(OnelineForm, for_type: float)

      assert match_t_value_t(OnelineForm, types(bytecode))
    end

    test "in a block form" do
      import Domo

      {:module, _, bytecode, _} =
        deftag BlockForm do
          for_type float
        end

      assert match_t_value_t(BlockForm, types(bytecode))
    end
  end

  defmodule K do
    use Domo

    typedstruct do
      field :first, integer
      field :second, float
    end
  end

  describe "typedstruct should" do
    test "define a structure with all keys enforced" do
      assert_raise ArgumentError, ~r/\[:second, :first\]/, fn ->
        K.__struct__(%{})
      end
    end

    test "define a typed structure" do
      {:module, _, bytecode, _} =
        defmodule P do
          use Domo

          typedstruct do
            field :first, integer
          end
        end

      assert [type: {:t, _, _}] = types(bytecode)
    end
  end

  defmodule Ovr do
    use Domo

    typedstruct do
      field :first, integer
      field :second, integer, default: 0
    end

    def new!(map), do: %__MODULE__{super(map) | second: 4}
  end

  describe "typedstruct should make new!/1" do
    test "constructor function to be in the module" do
      assert Kernel.function_exported?(Ovr, :new!, 1)
    end

    test "construct a structure" do
      assert K.new!(%{first: 1, second: 2.0}) == %K{first: 1, second: 2.0}
    end

    test "raise on missing key" do
      assert_raise ArgumentError, ~r/\[:first\]/, fn ->
        Ovr.new!(%{})
      end
    end

    test "overridable" do
      assert Ovr.new!(%{first: 3}) == %Ovr{first: 3, second: 4}
    end
  end

  describe "typedstruct should make put!/3" do
    test "function to be in the module" do
      assert Kernel.function_exported?(Ovr, :put!, 3)
    end

    test "can change each value in a struct" do
      st = Ovr.new!(%{first: 1})
      assert Ovr.put!(st, :first, 2) == %DomoTest.Ovr{first: 2, second: 4}
      assert Ovr.put!(st, :second, 2) == %DomoTest.Ovr{first: 1, second: 2}
    end

    test "raise if struct differs from the funciton's module" do
      assert_raise ArgumentError,
                   "DomoTest.Ovr structure was expected as the first argument and DomoTest.K was received.",
                   fn ->
                     Ovr.put!(K.new!(first: 1, second: 2.0), :second, 3)
                   end
    end

    test "raise for non present key" do
      assert_raise KeyError, ~r/:invalid_key/, fn ->
        assert Ovr.put!(Ovr.new!(%{first: 1}), :invalid_key, 1)
      end
    end
  end

  test "tag function should return tagged tuple by joining tag chain of up to 6 tags with a value" do
    import Domo
    assert tag(2.5, T1) == {T1, 2.5}
    assert tag(2.5, {T2, T1}) == {T2, {T1, 2.5}}
    assert tag(2.5, {T3, {T2, T1}}) == {T3, {T2, {T1, 2.5}}}
    assert tag(2.5, {T4, {T3, {T2, T1}}}) == {T4, {T3, {T2, {T1, 2.5}}}}
    assert tag(2.5, {T5, {T4, {T3, {T2, T1}}}}) == {T5, {T4, {T3, {T2, {T1, 2.5}}}}}
    assert tag(2.5, {T6, {T5, {T4, {T3, {T2, T1}}}}}) == {T6, {T5, {T4, {T3, {T2, {T1, 2.5}}}}}}
  end

  describe "untag! function should" do
    test "return value from tagged tuple on tag chain match with up to 6 tags in the chain" do
      import Domo
      assert untag!({T1, 2.5}, T1) == 2.5
      assert untag!({T2, {T1, 2.5}}, {T2, T1}) == 2.5
      assert untag!({T3, {T2, {T1, 2.5}}}, {T3, {T2, T1}}) == 2.5
      assert untag!({T4, {T3, {T2, {T1, 2.5}}}}, {T4, {T3, {T2, T1}}}) == 2.5
      assert untag!({T5, {T4, {T3, {T2, {T1, 2.5}}}}}, {T5, {T4, {T3, {T2, T1}}}}) == 2.5

      assert untag!({T6, {T5, {T4, {T3, {T2, {T1, 2.5}}}}}}, {T6, {T5, {T4, {T3, {T2, T1}}}}}) ==
               2.5
    end

    test "raise ArgumentError if tag chain not matches the tagged tuple" do
      assert_raise ArgumentError,
                   "Tag chain {:foo, :bar} doesn't match one in the tagged tuple {T2, {T1, 2.5}}.",
                   fn ->
                     Domo.untag!({T2, {T1, 2.5}}, {:foo, :bar})
                   end
    end
  end

  # default value passed to field should be checked to match type of the field.

  # new! should raise for values of map keys that are of tagged tuple type
  # when first level deep tag of value is not matching tag from spec.

  # update! should raise for untagged value when expected one by struct
  # definition

  # construction of struct with %{} map syntax should call to new!

  # changing structure with map syntax should call update!
end
