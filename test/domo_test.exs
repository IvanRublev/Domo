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

  describe "typedstruct should" do
    test "define a structure with all keys enforced" do
      assert_raise ArgumentError, ~r/\[:second, :first\]/, fn ->
        TwoFieldStruct.__struct__(%{})
      end
    end

    test "define a typed structure" do
      {:module, _, bytecode, _} =
        defmodule Typed do
          use Domo

          typedstruct do
            field :first, integer
          end
        end

      assert true == Enum.any?(types(bytecode), &match?({:type, {:t, _, _}}, &1))
    end

    test "bypass definitions down to TypedStruct.typedstruct macro" do
      assert true == TwoFieldStruct.plugin_injected?()
    end
  end

  describe "typedstruct should make new/1" do
    test "constructor function to be in the module" do
      true = Code.ensure_loaded?(TwoFieldStruct)
      assert true == Kernel.function_exported?(TwoFieldStruct, :new, 1)
    end

    test "construct a structure" do
      assert {:ok, %TwoFieldStruct{first: 1, second: 2.0}} ==
               TwoFieldStruct.new(%{first: 1, second: 2.0})

      assert {:ok, %TwoFieldStruct{first: 1, second: 2.0}} ==
               TwoFieldStruct.new(first: 1, second: 2.0)
    end

    test "return error on a missing key" do
      assert {:error, {:key_err, "the following keys must also be given \
when building struct OverridenNew: [:first]"}} = OverridenNew.new(%{})
    end

    test "return error on default value that doesn't match the field's type" do
      assert {:error, {:value_err, "Can't construct %IncorrectDefault{...} with \
new(%{second: \"hello\", third: 1.0})\n    Unexpected value type for the field :default. The value 1 doesn't match \
the Generator.an_atom() type."}} == IncorrectDefault.new(%{second: "hello", third: 1.0})
    end

    test "return error on argument values that doesn't match the fields type" do
      assert {:error, {:value_err, "Can't construct %IncorrectDefault{...} with new\
(%{default: :hello, second: :hello, third: 1})\
\n    Unexpected value type for the field :second. The value :hello doesn't \
match the Generator.a_str() type.\n    Unexpected value type for the field :third. \
The value 1 doesn't match the float type."}} ==
               IncorrectDefault.new(%{default: :hello, second: :hello, third: 1})
    end
  end

  describe "typedstruct should make new!/1" do
    test "constructor function to be in the module" do
      true = Code.ensure_loaded?(TwoFieldStruct)
      assert true == Kernel.function_exported?(TwoFieldStruct, :new!, 1)
    end

    test "construct a structure" do
      assert %TwoFieldStruct{first: 1, second: 2.0} ==
               TwoFieldStruct.new!(%{first: 1, second: 2.0})

      assert %TwoFieldStruct{first: 1, second: 2.0} ==
               TwoFieldStruct.new!(first: 1, second: 2.0)
    end

    test "raise on missing key" do
      assert_raise ArgumentError, ~r/\[:first\]/, fn ->
        OverridenNew.new!(%{})
      end
    end

    test "raise on default value that doesn't match the field's type" do
      assert_raise ArgumentError,
                   "Can't construct %IncorrectDefault{...} with new!(%{second: \"hello\", \
third: 1.0})\n    Unexpected value type for the field :default. The value 1 doesn't match \
the Generator.an_atom() type.",
                   fn ->
                     IncorrectDefault.new!(%{second: "hello", third: 1.0})
                   end
    end

    test "raise on argument values that doesn't match the fields type" do
      assert_raise ArgumentError,
                   "Can't construct %IncorrectDefault{...} with new!(%{default: :hello, \
second: :hello, third: 1})\n    Unexpected value type for the field :second. The value :hello \
doesn't match the Generator.a_str() type.\n    Unexpected value type for the field :third. \
The value 1 doesn't match the float type.",
                   fn ->
                     IncorrectDefault.new!(%{default: :hello, second: :hello, third: 1})
                   end
    end
  end

  describe "typedstruct should make put/3" do
    test "function to be in the module" do
      true = Code.ensure_loaded?(OverridenNew)
      assert true == Kernel.function_exported?(OverridenNew, :put, 3)
    end

    test "to be able to change each value in a struct" do
      st = TwoFieldStruct.new!(%{first: 1, second: 0.0})
      assert {:ok, %TwoFieldStruct{first: 2, second: 0.0}} == TwoFieldStruct.put(st, :first, 2)
      assert {:ok, %TwoFieldStruct{first: 1, second: 2.0}} == TwoFieldStruct.put(st, :second, 2.0)
    end

    test "return error if argument struct name differs" do
      assert {:error, {:unexpected_struct, "OverridenNew structure was expected \
as the first argument and TwoFieldStruct was received."}} ==
               OverridenNew.put(TwoFieldStruct.new!(first: 1, second: 2.0), :second, 3)
    end

    test "return error for non present key" do
      {:error, {:key_err, err}} =
        TwoFieldStruct.put(TwoFieldStruct.new!(first: 1, second: 2.0), :invalid_key, 1)

      assert true == Regex.match?(~r/:invalid_key/, err)
    end

    test "return error on value that doesn't match the field's type" do
      {:error, {:value_err, err}} =
        TwoFieldStruct.put(TwoFieldStruct.new!(first: 1, second: 2.0), :first, 1.0)

      assert "Unexpected value type for the field :first. The value 1.0 \
doesn't match the integer type." == err
    end
  end

  describe "typedstruct should make put!/3" do
    test "function to be in the module" do
      true = Code.ensure_loaded?(OverridenNew)
      assert true == Kernel.function_exported?(OverridenNew, :put!, 3)
    end

    test "to be able to change each value in a struct" do
      st = TwoFieldStruct.new!(%{first: 0, second: 0.0})
      assert %TwoFieldStruct{first: 0, second: 4.0} == TwoFieldStruct.put!(st, :second, 4.0)
      assert %TwoFieldStruct{first: 1, second: 0.0} == TwoFieldStruct.put!(st, :first, 1)
    end

    test "raise if argument struct name differs" do
      assert_raise ArgumentError,
                   "OverridenNew structure was expected as the first argument and TwoFieldStruct was received.",
                   fn ->
                     OverridenNew.put!(TwoFieldStruct.new!(first: 1, second: 2.0), :second, 3)
                   end
    end

    test "raise for non present key" do
      assert_raise KeyError, ~r/:invalid_key/, fn ->
        assert TwoFieldStruct.put!(TwoFieldStruct.new!(first: 1, second: 2.0), :invalid_key, 1)
      end
    end

    test "raise on value that doesn't match the field's type" do
      assert_raise ArgumentError,
                   "Unexpected value type for the field :first. The value 1.0 doesn't match the integer type.",
                   fn ->
                     TwoFieldStruct.put!(TwoFieldStruct.new!(first: 1, second: 2.0), :first, 1.0)
                   end
    end
  end

  describe "typedstruct should make merge/2" do
    test "function to be in the module" do
      true = Code.ensure_loaded?(OverridenNew)
      assert true == Kernel.function_exported?(OverridenNew, :merge, 2)
    end

    test "to be able to update struct values skipping nonexisting keys" do
      assert {:ok, %TwoFieldStruct{first: 2, second: 4.0}} ==
               TwoFieldStruct.merge(TwoFieldStruct.new!(%{first: 1, second: 0.0}),
                 first: 2,
                 second: 4.0,
                 third: 5
               )
    end

    test "to keep the struct the same if no overlapping keys in passed enumerable" do
      assert {:ok, %TwoFieldStruct{first: 1, second: 2.0}} ==
               TwoFieldStruct.merge(
                 TwoFieldStruct.new!(first: 1, second: 2.0),
                 %{non: 2, existing: 4, key: 5}
               )
    end

    test "return error if the given struct's name differs from the module's name" do
      assert {:error, {:unexpected_struct, "IncorrectDefault structure was expected as the first \
argument and TwoFieldStruct was received."}} ==
               IncorrectDefault.merge(TwoFieldStruct.new!(first: 1, second: 2.0), second: 3)
    end

    test "return error on value that doesn't match the field's type" do
      assert {:error, {:value_err, "Unexpected value type for the field :first. \
The value 2.0 doesn't match the integer type.\nUnexpected value type for the field :second. \
The value :three doesn't match the float type."}} ==
               TwoFieldStruct.merge(TwoFieldStruct.new!(first: 1, second: 2.0),
                 first: 2.0,
                 second: :three
               )
    end
  end

  describe "typedstruct should make merge!/2" do
    test "function to be in the module" do
      true = Code.ensure_loaded?(OverridenNew)
      assert true == Kernel.function_exported?(OverridenNew, :merge!, 2)
    end

    test "to be able to update struct values skipping nonexisting keys" do
      assert %TwoFieldStruct{first: 2, second: 4.0} ==
               TwoFieldStruct.merge!(TwoFieldStruct.new!(%{first: 1, second: 2.0}),
                 first: 2,
                 second: 4.0,
                 third: 5
               )
    end

    test "to keep the struct the same if no overlapping keys in passed enumerable" do
      assert %TwoFieldStruct{first: 1, second: 2.0} ==
               TwoFieldStruct.merge!(
                 TwoFieldStruct.new!(first: 1, second: 2.0),
                 %{non: 2, existing: 4, key: 5}
               )
    end

    test "raise if the given struct's name differs from the module's name" do
      assert_raise ArgumentError,
                   "IncorrectDefault structure was expected as the first argument and TwoFieldStruct was received.",
                   fn ->
                     IncorrectDefault.merge!(TwoFieldStruct.new!(first: 1, second: 2.0), second: 3)
                   end
    end

    test "raise on value that doesn't match the field's type" do
      assert_raise ArgumentError,
                   "Unexpected value type for the field :first. The value 2.0 doesn't match \
the integer type.\nUnexpected value type for the field :second. The value :three doesn't match the float type.",
                   fn ->
                     TwoFieldStruct.merge!(TwoFieldStruct.new!(first: 1, second: 2.0),
                       first: 2.0,
                       second: :three
                     )
                   end
    end
  end

  test "new(!)/1, merge(!)/2, and put(!)/3 functions should be overridable" do
    assert %OverridenNew{first: 3, second: 4} == OverridenNew.new!(%{first: 3})
    assert {:ok, %OverridenNew{first: 3, second: 4}} == OverridenNew.new(%{first: 3})

    assert %OverridenNew{first: 555, second: 4} ==
             OverridenNew.merge!(OverridenNew.new!(%{first: 3}), %{first: 4})

    assert {:ok, %OverridenNew{first: 666, second: 4}} ==
             OverridenNew.merge(OverridenNew.new!(%{first: 3}), %{first: 4})

    assert %OverridenNew{first: 24, second: 4} ==
             OverridenNew.put!(OverridenNew.new!(%{first: 3}), :first, 4)

    assert {:ok, %OverridenNew{first: 64, second: 4}} ==
             OverridenNew.put(OverridenNew.new!(%{first: 3}), :first, 4)
  end

  test "merge(!)/2 and put(!)/3 functions should Not be added to the struct if no fields are specified" do
    true = Code.ensure_loaded?(NoFieldsStruct)
    assert false == Kernel.function_exported?(NoFieldsStruct, :merge!, 2)
    assert false == Kernel.function_exported?(NoFieldsStruct, :merge, 2)
    assert false == Kernel.function_exported?(NoFieldsStruct, :put!, 3)
    assert false == Kernel.function_exported?(NoFieldsStruct, :put, 3)
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
