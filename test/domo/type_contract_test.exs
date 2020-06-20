defmodule CustomStruct do
  defstruct([:title])
  @type t :: %__MODULE__{title: String.t()}
end

defmodule Domo.TypeContractTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Domo.TypeContract

  describe "TypeContract for nonexisting module atom" do
    defmodule The.Nested.Mod, do: nil

    test "value should emit warning" do
      warns =
        capture_io(:stderr, fn ->
          _ = TypeContract.valid?(Mod, The.Nested.Mod, TypeList.env())
        end)

      assert warns =~ ~r/No loaded module for value Mod. Missing alias?/
    end

    test "in type should emit warning" do
      warns =
        capture_io(:stderr, fn ->
          _ = TypeContract.valid?(The.Nested.Mod, quote(do: Atom | List | Mod), TypeList.env())
        end)

      assert warns =~ ~r/No loaded module for type Mod. Missing alias?/
    end
  end

  describe "TypeContract with remote type should be" do
    test "validatable for nested collections with ors and user defined types" do
      assert true ==
               TypeContract.valid?(
                 {
                   :wrap,
                   {:foo, [:atom], {:nested, %{p_name: "Person name"}}}
                 },
                 quote(do: TypeList.person_or_map()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 {
                   1,
                   {:bar, [:baz, :wheee], {2.45, %TypeList.Person{name: "Person name"}}}
                 },
                 quote(do: TypeList.person_or_map()),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 {
                   :wrap,
                   {:foo, [:atom], {:nested, %{}}}
                 },
                 quote(do: TypeList.person_or_map()),
                 TypeList.env()
               )
    end

    test "validatable for system types" do
      assert true == TypeContract.valid?("hello", quote(do: String.t()), TypeList.env())
      assert true == TypeContract.valid?("hello", quote(do: TypeList.a_str()), TypeList.env())
      assert true == TypeContract.valid?(:atom, quote(do: TypeList.an_atom()), TypeList.env())
      assert true == TypeContract.valid?(1, quote(do: TypeList.an_integer()), TypeList.env())
      assert true == TypeContract.valid?(1.0, quote(do: TypeList.a_float()), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 <<0::size(1)>>,
                 quote(do: TypeList.a_bitstring()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(fn -> nil end, quote(do: TypeList.a_fun()), TypeList.env())

      assert true == TypeContract.valid?(self(), quote(do: TypeList.a_pid()), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 :erlang.list_to_port('#Port<0.0>'),
                 quote(do: TypeList.a_port()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 :erlang.list_to_ref('#Ref<0.0.0.0>'),
                 quote(do: TypeList.a_reference()),
                 TypeList.env()
               )

      assert true == TypeContract.valid?({}, quote(do: TypeList.a_tuple()), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: TypeList.a_list()), TypeList.env())
      assert true == TypeContract.valid?(%{}, quote(do: TypeList.a_map()), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %TypeList.Person{name: "name"},
                 quote(do: TypeList.cust_person()),
                 TypeList.env()
               )

      assert false == TypeContract.valid?(<<0::size(7)>>, quote(do: String.t()), TypeList.env())

      assert false ==
               TypeContract.valid?(<<0::size(7)>>, quote(do: TypeList.a_str()), TypeList.env())

      assert false == TypeContract.valid?(1, quote(do: TypeList.an_atom()), TypeList.env())
      assert false == TypeContract.valid?(:one, quote(do: TypeList.an_integer()), TypeList.env())
      assert false == TypeContract.valid?(1, quote(do: TypeList.a_float()), TypeList.env())
      assert false == TypeContract.valid?(nil, quote(do: TypeList.a_bitstring()), TypeList.env())
      assert false == TypeContract.valid?(:fn, quote(do: TypeList.a_fun()), TypeList.env())
      assert false == TypeContract.valid?(:pid, quote(do: TypeList.a_pid()), TypeList.env())
      assert false == TypeContract.valid?("", quote(do: TypeList.a_port()), TypeList.env())
      assert false == TypeContract.valid?(:ref, quote(do: TypeList.a_reference()), TypeList.env())
      assert false == TypeContract.valid?("tuple", quote(do: TypeList.a_tuple()), TypeList.env())
      assert false == TypeContract.valid?(0, quote(do: TypeList.a_list()), TypeList.env())
      assert false == TypeContract.valid?(:mp, quote(do: TypeList.a_map()), TypeList.env())
      assert false == TypeContract.valid?(%{}, quote(do: TypeList.cust_person()), TypeList.env())
    end

    test "validatable for user composed types" do
      assert true == TypeContract.valid?("hello", quote(do: TypeList.s()), TypeList.env())

      assert true ==
               TypeContract.valid?("hello", quote(do: TypeList.opaque_str()), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %{a_key: "value"},
                 quote(do: TypeList.map_as_bool()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{
                   :struct => %TypeList.Person{name: "foo"},
                   "s" => :atom,
                   1 => 1.0,
                   <<0::size(7)>> => fn _x -> nil end,
                   self() => :erlang.list_to_port('#Port<0.0>'),
                   :erlang.list_to_ref('#Ref<0.0.0.0>') => {},
                   [] => %{}
                 },
                 quote(do: TypeList.map_all()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %TypeList.StructAll{
                   atom: :struct,
                   peer: %TypeList.Person{name: "foo"},
                   string: "s",
                   integer: 1,
                   float: 1.0,
                   bitstring: <<0::size(7)>>,
                   fun: fn _x -> nil end,
                   pid: self(),
                   port: :erlang.list_to_port('#Port<0.0>'),
                   ref: :erlang.list_to_ref('#Ref<0.0.0.0>'),
                   tuple: {},
                   list: [],
                   map: %{}
                 },
                 quote(do: TypeList.struct_all()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 {:struct,
                  {%TypeList.Person{name: "foo"},
                   {"s",
                    {1,
                     {1.0,
                      {<<0::size(7)>>,
                       {fn _x -> nil end,
                        {self(),
                         {:erlang.list_to_port('#Port<0.0>'),
                          {:erlang.list_to_ref('#Ref<0.0.0.0>'), {{}, {[], %{}}}}}}}}}}}}},
                 quote(do: TypeList.tuple_all()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [%TypeList.Person{name: "foo"}, %TypeList.Person{name: "bar"}],
                 quote(do: TypeList.list_cust_person()),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [
                   atom: :struct,
                   peer: %TypeList.Person{name: "foo"},
                   string: "s",
                   integer: 1,
                   float: 1.0,
                   bitstring: <<0::size(7)>>,
                   fun: fn _x -> nil end,
                   pid: self(),
                   port: :erlang.list_to_port('#Port<0.0>'),
                   ref: :erlang.list_to_ref('#Ref<0.0.0.0>'),
                   tuple: {},
                   list: [],
                   map: %{}
                 ],
                 quote(do: TypeList.kw_list_all()),
                 TypeList.env()
               )

      assert false == TypeContract.valid?(<<0::size(7)>>, quote(do: TypeList.s()), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 <<0::size(7)>>,
                 quote(do: TypeList.opaque_str()),
                 TypeList.env()
               )

      assert false == TypeContract.valid?(%{}, quote(do: TypeList.map_as_bool()), TypeList.env())
      assert false == TypeContract.valid?(%{}, quote(do: TypeList.map_all()), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 %TypeList.Person{name: "foo"},
                 quote(do: TypeList.struct_all()),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?([%{}], quote(do: TypeList.list_cust_person()), TypeList.env())

      assert false ==
               TypeContract.valid?([foo: :bar], quote(do: TypeList.kw_list_all()), TypeList.env())
    end
  end

  def some_fun(_a, _b), do: nil

  describe "TypeContract should be" do
    setup do
      %{
        pid: self(),
        port: :erlang.list_to_port('#Port<0.0>'),
        reference: :erlang.list_to_ref('#Ref<0.0.0.0>')
      }
    end

    for val <- [
          :some_atom,
          0,
          1.0,
          Macro.escape(<<0::size(1)>>),
          &__MODULE__.some_fun/2,
          Macro.escape({}),
          [],
          Macro.escape(%{}),
          Macro.escape(%CustomStruct{})
        ] do
      test "validatable with #{inspect(val)} for any, none, and no_return" do
        assert true == TypeContract.valid?(unquote(val), quote(do: any), TypeList.env())
        assert true == TypeContract.valid?(unquote(val), quote(do: term), TypeList.env())

        assert false == TypeContract.valid?(unquote(val), quote(do: none), TypeList.env())
        assert false == TypeContract.valid?(unquote(val), quote(do: no_return), TypeList.env())
      end
    end

    test "validatable with pid, port, reference for any, none, and no_return", %{
      pid: pid,
      port: port,
      reference: reference
    } do
      for val <- [
            pid,
            port,
            reference
          ] do
        assert true == TypeContract.valid?(val, quote(do: any), TypeList.env())
        assert true == TypeContract.valid?(val, quote(do: term), TypeList.env())

        assert false == TypeContract.valid?(val, quote(do: none), TypeList.env())
        assert false == TypeContract.valid?(val, quote(do: no_return), TypeList.env())
      end
    end

    test "validatable for atom" do
      assert true == TypeContract.valid?(:some_atom, quote(do: atom), TypeList.env())
      assert true == TypeContract.valid?(:some_atom, quote(do: atom | float), TypeList.env())
      assert true == TypeContract.valid?(:some_atom, quote(do: module), TypeList.env())
      assert true == TypeContract.valid?(:some_atom, quote(do: node), TypeList.env())
      assert true == TypeContract.valid?(:some_atom, quote(do: :some_atom), TypeList.env())
      assert true == TypeContract.valid?(nil, quote(do: nil), TypeList.env())
      assert true == TypeContract.valid?(true, quote(do: true), TypeList.env())
      assert true == TypeContract.valid?(false, quote(do: false), TypeList.env())
      assert true == TypeContract.valid?(true, quote(do: boolean), TypeList.env())
      assert true == TypeContract.valid?(false, quote(do: boolean), TypeList.env())

      assert true ==
               TypeContract.valid?(:some_atom, quote(do: as_boolean(:some_atom)), TypeList.env())

      assert true == TypeContract.valid?(:infinity, quote(do: timeout), TypeList.env())

      assert false == TypeContract.valid?(:some_atom, quote(do: integer | float), TypeList.env())
      assert false == TypeContract.valid?(:some_atom, quote(do: pid), TypeList.env())
      assert false == TypeContract.valid?(:other_atom, quote(do: :some_atom), TypeList.env())
      assert false == TypeContract.valid?(:not_nil, quote(do: nil), TypeList.env())
      assert false == TypeContract.valid?(false, quote(do: true), TypeList.env())
      assert false == TypeContract.valid?(true, quote(do: false), TypeList.env())
      assert false == TypeContract.valid?(:some_atom, quote(do: boolean), TypeList.env())
      assert false == TypeContract.valid?(:some_atom, quote(do: timeout), TypeList.env())

      assert false ==
               TypeContract.valid?(:other_atom, quote(do: as_boolean(:some_atom)), TypeList.env())
    end

    test "validatable for various integers" do
      assert true == TypeContract.valid?(1, quote(do: integer), TypeList.env())
      assert true == TypeContract.valid?(1, quote(do: integer | atom), TypeList.env())
      assert true == TypeContract.valid?(-1, quote(do: neg_integer), TypeList.env())
      assert true == TypeContract.valid?(1, quote(do: pos_integer), TypeList.env())
      assert true == TypeContract.valid?(0, quote(do: non_neg_integer), TypeList.env())
      assert true == TypeContract.valid?(0, quote(do: timeout), TypeList.env())
      assert true == TypeContract.valid?(1, quote(do: 1), TypeList.env())
      assert true == TypeContract.valid?(2, quote(do: 2..3), TypeList.env())
      assert true == TypeContract.valid?(2, quote(do: as_boolean(0..3)), TypeList.env())
      assert true == TypeContract.valid?(10, quote(do: arity), TypeList.env())
      assert true == TypeContract.valid?(10, quote(do: byte), TypeList.env())
      assert true == TypeContract.valid?(0x10FFFF, quote(do: char), TypeList.env())
      assert true == TypeContract.valid?(0, quote(do: number), TypeList.env())

      assert false == TypeContract.valid?(1, quote(do: float | atom), TypeList.env())
      assert false == TypeContract.valid?(1, quote(do: pid), TypeList.env())
      assert false == TypeContract.valid?(0, quote(do: neg_integer), TypeList.env())
      assert false == TypeContract.valid?(0, quote(do: pos_integer), TypeList.env())
      assert false == TypeContract.valid?(-1, quote(do: non_neg_integer), TypeList.env())
      assert false == TypeContract.valid?(-1, quote(do: timeout), TypeList.env())
      assert false == TypeContract.valid?(0, quote(do: 1), TypeList.env())
      assert false == TypeContract.valid?(4, quote(do: 2..3), TypeList.env())
      assert false == TypeContract.valid?(4, quote(do: as_boolean(0..3)), TypeList.env())
      assert false == TypeContract.valid?(1, quote(do: 0..0), TypeList.env())
      assert false == TypeContract.valid?(300, quote(do: arity), TypeList.env())
      assert false == TypeContract.valid?(300, quote(do: byte), TypeList.env())
      assert false == TypeContract.valid?(0xFFFFFF, quote(do: char), TypeList.env())
    end

    test "validatable for float" do
      assert true == TypeContract.valid?(1.0, quote(do: float), TypeList.env())
      assert true == TypeContract.valid?(1.0, quote(do: float | atom), TypeList.env())
      assert true == TypeContract.valid?(1.0, quote(do: number), TypeList.env())
      assert true == TypeContract.valid?(1.0, quote(do: as_boolean(float)), TypeList.env())

      assert false == TypeContract.valid?(1.0, quote(do: pid), TypeList.env())
      assert false == TypeContract.valid?(1.0, quote(do: as_boolean(pid)), TypeList.env())
      assert false == TypeContract.valid?(1.0, quote(do: integer | atom), TypeList.env())
    end

    test "mismatching number for not an integer or not a float", %{pid: pid} do
      assert false == TypeContract.valid?(pid, quote(do: number), TypeList.env())
    end

    test "validatable for bit string" do
      assert true == TypeContract.valid?("", quote(do: <<>>), TypeList.env())
      assert true == TypeContract.valid?("", quote(do: <<_::0>>), TypeList.env())
      assert true == TypeContract.valid?(<<0::size(16)>>, quote(do: <<_::16>>), TypeList.env())
      # sequence of k*3 bits
      assert true == TypeContract.valid?(<<0::size(6)>>, quote(do: <<_::_*3>>), TypeList.env())
      # sequense of 5 + (k*4) bits
      assert true ==
               TypeContract.valid?(<<0::size(13)>>, quote(do: <<_::5, _::_*4>>), TypeList.env())

      assert true == TypeContract.valid?("Hello", quote(do: binary), TypeList.env())
      assert true == TypeContract.valid?(<<0::size(1)>>, quote(do: bitstring), TypeList.env())
      assert true == TypeContract.valid?("Hello", quote(do: as_boolean(binary)), TypeList.env())

      assert true ==
               TypeContract.valid?("Hello", quote(do: as_boolean(binary) | atom), TypeList.env())

      assert false == TypeContract.valid?("some", quote(do: <<>>), TypeList.env())
      assert false == TypeContract.valid?("some", quote(do: <<_::0>>), TypeList.env())
      assert false == TypeContract.valid?(<<0::size(17)>>, quote(do: <<_::16>>), TypeList.env())
      assert false == TypeContract.valid?(<<0::size(7)>>, quote(do: <<_::_*3>>), TypeList.env())

      assert false ==
               TypeContract.valid?(<<0::size(14)>>, quote(do: <<_::5, _::_*4>>), TypeList.env())

      assert false == TypeContract.valid?(<<0::size(7)>>, quote(do: binary), TypeList.env())
      assert false == TypeContract.valid?("", quote(do: bitstring), TypeList.env())

      assert false ==
               TypeContract.valid?(<<0::size(7)>>, quote(do: as_boolean(binary)), TypeList.env())

      assert false == TypeContract.valid?("Hello", quote(do: integer | atom), TypeList.env())
    end

    test "validatable for function" do
      assert true == TypeContract.valid?(fn -> nil end, quote(do: fun), TypeList.env())
      assert true == TypeContract.valid?(fn -> nil end, quote(do: function), TypeList.env())

      assert true ==
               TypeContract.valid?(fn -> nil end, quote(do: function | atom), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 fn _a, _b -> 1 end,
                 quote(do: (... -> integer)),
                 TypeList.env()
               )

      # return type is not checked
      assert true == TypeContract.valid?(fn -> nil end, quote(do: (... -> float)), TypeList.env())
      assert true == TypeContract.valid?(fn -> nil end, quote(do: (() -> none)), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 fn _a, _b -> nil end,
                 quote(do: (none, none -> none)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 fn -> nil end,
                 quote(do: as_boolean((() -> none))),
                 TypeList.env()
               )

      assert false == TypeContract.valid?(fn -> nil end, quote(do: pid), TypeList.env())
      # arity should be checked
      assert false ==
               TypeContract.valid?(fn _a -> nil end, quote(do: (() -> none)), TypeList.env())

      assert false ==
               TypeContract.valid?(fn -> nil end, quote(do: integer | atom), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 fn _a, _b, _c -> nil end,
                 quote(do: (none, none -> none)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 fn _a -> nil end,
                 quote(do: as_boolean((() -> none))),
                 TypeList.env()
               )
    end

    test "validatable for PID", %{pid: pid} do
      assert true == TypeContract.valid?(pid, quote(do: pid), TypeList.env())
      assert true == TypeContract.valid?(pid, quote(do: as_boolean(pid)), TypeList.env())
      assert true == TypeContract.valid?(pid, quote(do: identifier), TypeList.env())
      assert true == TypeContract.valid?(pid, quote(do: identifier | atom), TypeList.env())

      assert false == TypeContract.valid?(pid, quote(do: integer), TypeList.env())
      assert false == TypeContract.valid?(pid, quote(do: as_boolean(integer)), TypeList.env())
      assert false == TypeContract.valid?(pid, quote(do: integer | atom), TypeList.env())
    end

    test "validatable for Port", %{port: port} do
      assert true == TypeContract.valid?(port, quote(do: port), TypeList.env())
      assert true == TypeContract.valid?(port, quote(do: as_boolean(port)), TypeList.env())
      assert true == TypeContract.valid?(port, quote(do: identifier), TypeList.env())
      assert true == TypeContract.valid?(port, quote(do: identifier | atom), TypeList.env())

      assert false == TypeContract.valid?(port, quote(do: integer), TypeList.env())
      assert false == TypeContract.valid?(port, quote(do: as_boolean(integer)), TypeList.env())
      assert false == TypeContract.valid?(port, quote(do: integer | atom), TypeList.env())
    end

    test "validatable for Reference", %{reference: reference} do
      assert true == TypeContract.valid?(reference, quote(do: reference), TypeList.env())

      assert true ==
               TypeContract.valid?(reference, quote(do: as_boolean(reference)), TypeList.env())

      assert true == TypeContract.valid?(reference, quote(do: identifier), TypeList.env())
      assert true == TypeContract.valid?(reference, quote(do: identifier | atom), TypeList.env())

      assert false == TypeContract.valid?(reference, quote(do: integer), TypeList.env())

      assert false ==
               TypeContract.valid?(reference, quote(do: as_boolean(integer)), TypeList.env())

      assert false == TypeContract.valid?(reference, quote(do: integer | atom), TypeList.env())
    end

    test "validatable for Tuple" do
      assert true == TypeContract.valid?({}, quote(do: tuple), TypeList.env())
      assert true == TypeContract.valid?({1}, quote(do: tuple), TypeList.env())
      assert true == TypeContract.valid?({}, quote(do: {}), TypeList.env())
      assert true == TypeContract.valid?({:ok}, quote(do: {:ok}), TypeList.env())
      assert true == TypeContract.valid?({:error}, quote(do: {:ok | :error}), TypeList.env())
      assert true == TypeContract.valid?({:ok, 1}, quote(do: {:ok, integer}), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 {:ok, :end},
                 quote(do: {:ok | :error, integer | atom}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 {:ok, 1.0, :end},
                 quote(do: {:ok | :error, integer | float, atom}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 {:ok, {1.0, {:end}}},
                 quote(do: {atom, {integer | float, {atom}}}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 {:ok, 1, 2.5},
                 quote(do: {:ok, integer, float}),
                 TypeList.env()
               )

      assert true == TypeContract.valid?({:ok}, quote(do: as_boolean({:ok})), TypeList.env())
      assert true == TypeContract.valid?({Enum, :at, 3}, quote(do: mfa), TypeList.env())
      assert true == TypeContract.valid?({}, quote(do: atom | tuple), TypeList.env())

      assert false == TypeContract.valid?({}, quote(do: pid), TypeList.env())
      assert false == TypeContract.valid?({1}, quote(do: {}), TypeList.env())
      assert false == TypeContract.valid?({:err}, quote(do: {:infinity}), TypeList.env())
      assert false == TypeContract.valid?({:infinity}, quote(do: {:ok | :error}), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 {:ok, 1.0},
                 quote(do: {:ok | :error, integer | atom}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 {:some_atom, 1, :end},
                 quote(do: {:ok | :error, integer | float, atom}),
                 TypeList.env()
               )

      assert false == TypeContract.valid?({:ok, :atom}, quote(do: {:ok, integer}), TypeList.env())

      assert false ==
               TypeContract.valid?({:ok, 10, 20}, quote(do: {:ok, integer}), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 {:ok, 1, :not_float},
                 quote(do: {:ok, integer, float}),
                 TypeList.env()
               )

      assert false == TypeContract.valid?({}, quote(do: mfa), TypeList.env())
      assert false == TypeContract.valid?({Enum, :at, :what}, quote(do: mfa), TypeList.env())
      assert false == TypeContract.valid?({}, quote(do: as_boolean(mfa)), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 {:ok, {1.0, {1}}},
                 quote(do: {atom, {integer | float, {atom}}}),
                 TypeList.env()
               )

      assert false == TypeContract.valid?({}, quote(do: atom | integer), TypeList.env())
    end

    test "validatable for proper List" do
      assert true == TypeContract.valid?([], quote(do: []), TypeList.env())
      assert true == TypeContract.valid?([:hello], quote(do: [atom]), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: [atom]), TypeList.env())
      assert true == TypeContract.valid?([1, :hello], quote(do: list), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: list), TypeList.env())
      assert true == TypeContract.valid?([:hello], quote(do: list(atom)), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: list(atom)), TypeList.env())
      assert true == TypeContract.valid?([0], quote(do: [...]), TypeList.env())
      assert true == TypeContract.valid?([0], quote(do: [integer, ...]), TypeList.env())
      assert true == TypeContract.valid?([0], quote(do: nonempty_list(integer)), TypeList.env())
      assert true == TypeContract.valid?([0, :hello], quote(do: nonempty_list), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: list(any)), TypeList.env())
      assert true == TypeContract.valid?([0, 0x10FFFF], quote(do: charlist), TypeList.env())

      assert true ==
               TypeContract.valid?([0, 0x10FFFF], quote(do: nonempty_charlist), TypeList.env())

      assert true == TypeContract.valid?([:hello, 1], quote(do: [atom | integer]), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 [:hello, 1, 1.0],
                 quote(do: [float | atom | integer]),
                 TypeList.env()
               )

      assert true == TypeContract.valid?([[1, 2], [3]], quote(do: [[integer]]), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: atom | list), TypeList.env())

      assert false == TypeContract.valid?([1], quote(do: []), TypeList.env())
      assert false == TypeContract.valid?([:hello, 0], quote(do: [atom]), TypeList.env())
      assert false == TypeContract.valid?([], quote(do: [...]), TypeList.env())
      assert false == TypeContract.valid?([1 | 2], quote(do: [...]), TypeList.env())
      assert false == TypeContract.valid?([], quote(do: [integer, ...]), TypeList.env())
      assert false == TypeContract.valid?([:atom], quote(do: [integer, ...]), TypeList.env())
      assert false == TypeContract.valid?([1 | 2], quote(do: [integer, ...]), TypeList.env())
      assert false == TypeContract.valid?([], quote(do: nonempty_list(integer)), TypeList.env())

      assert false ==
               TypeContract.valid?([:atom], quote(do: nonempty_list(integer)), TypeList.env())

      assert false ==
               TypeContract.valid?([1 | 2], quote(do: nonempty_list(integer)), TypeList.env())

      assert false == TypeContract.valid?([], quote(do: nonempty_list), TypeList.env())
      assert false == TypeContract.valid?([1 | 2], quote(do: list), TypeList.env())
      assert false == TypeContract.valid?([1], quote(do: list(atom)), TypeList.env())
      assert false == TypeContract.valid?([1], quote(do: list(atom)), TypeList.env())
      assert false == TypeContract.valid?([0xFFFFFF], quote(do: charlist), TypeList.env())

      assert false ==
               TypeContract.valid?([0xFFFFFF], quote(do: nonempty_charlist), TypeList.env())

      assert false == TypeContract.valid?([], quote(do: nonempty_charlist), TypeList.env())

      assert false ==
               TypeContract.valid?([:hello, 1, 1.0], quote(do: [atom | integer]), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 [:hello, "", 1.0],
                 quote(do: [float | atom | integer]),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?([[1, 2], [:nan]], quote(do: [[integer]]), TypeList.env())

      assert false == TypeContract.valid?([], quote(do: atom | integer), TypeList.env())
    end

    test "validatable for maybe improper list" do
      assert true ==
               TypeContract.valid?(
                 [1 | :finish],
                 quote(do: maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [1, 2],
                 quote(do: maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [],
                 quote(do: maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [1 | :finish],
                 quote(do: nonempty_maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [1, 2],
                 quote(do: nonempty_maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [1 | :finish],
                 quote(do: nonempty_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?([1, :finish], quote(do: maybe_improper_list), TypeList.env())

      assert true ==
               TypeContract.valid?([], quote(do: maybe_improper_list), TypeList.env())

      assert true ==
               TypeContract.valid?([1 | :finish], quote(do: maybe_improper_list), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 [1 | :atom],
                 quote(do: nonempty_maybe_improper_list),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [1, 2],
                 quote(do: nonempty_maybe_improper_list),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [1 | 2],
                 quote(do: maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [],
                 quote(do: nonempty_maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [1 | 2],
                 quote(do: nonempty_maybe_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [],
                 quote(do: nonempty_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [1, 2],
                 quote(do: nonempty_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [1 | 2],
                 quote(do: nonempty_improper_list(integer, atom)),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [],
                 quote(do: nonempty_maybe_improper_list),
                 TypeList.env()
               )
    end

    test "validatable for iolist and iodata" do
      assert true == TypeContract.valid?([1, 2, 3 | "end"], quote(do: iolist), TypeList.env())
      assert true == TypeContract.valid?(["start" | "end"], quote(do: iolist), TypeList.env())
      assert true == TypeContract.valid?([[1 | "end"] | "end"], quote(do: iolist), TypeList.env())
      assert true == TypeContract.valid?([1, 2, 3 | []], quote(do: iolist), TypeList.env())
      assert true == TypeContract.valid?(["start" | []], quote(do: iolist), TypeList.env())

      assert true ==
               TypeContract.valid?([["inner" | "lst"] | []], quote(do: iolist), TypeList.env())

      assert true == TypeContract.valid?([], quote(do: iolist), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: iodata), TypeList.env())
      assert true == TypeContract.valid?([[1 | "end"] | "end"], quote(do: iodata), TypeList.env())
      assert true == TypeContract.valid?("binary", quote(do: iodata), TypeList.env())

      assert false == TypeContract.valid?([1 | <<0::size(7)>>], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?([:hello | "end"], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?([1 | :end], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?(["1" | :end], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?([[1 | "end"] | :end], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?([:hello | []], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?([:notio], quote(do: iolist), TypeList.env())
      assert false == TypeContract.valid?([:notio], quote(do: iodata), TypeList.env())
    end

    test "validatable for keywordlist" do
      assert true == TypeContract.valid?([key: :atom], quote(do: [key: atom]), TypeList.env())
      assert true == TypeContract.valid?([], quote(do: [key: atom]), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 [key: :atom],
                 quote(do: [key: atom, second: integer]),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [second: 1],
                 quote(do: [key: atom, second: integer]),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [one: 1, two: "three"],
                 quote(do: [{atom, any}]),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?([one: 1, two: "three"], quote(do: keyword), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 [one: "1", two: "three"],
                 quote(do: keyword(binary)),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 [one: 1, two: "one"],
                 quote(do: keyword(integer | binary)),
                 TypeList.env()
               )

      assert false == TypeContract.valid?([key: 1], quote(do: [key: atom]), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 [key: 1.0],
                 quote(do: [key: atom, second: integer]),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 [key: 1.0, unexp: :val],
                 quote(do: [key: atom, second: integer]),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?([{"one", "two"}], quote(do: [{atom, any}]), TypeList.env())

      assert false == TypeContract.valid?([{"one", "two"}], quote(do: keyword), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 [one: 1.0],
                 quote(do: keyword(integer | binary)),
                 TypeList.env()
               )
    end

    test "validatable for map" do
      assert true == TypeContract.valid?(%{}, quote(do: %{}), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %{one: 1, two: 1.0},
                 quote(do: %{one: integer, two: float}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{"1.0" => 1.0, "2.0" => 2.0},
                 quote(do: %{required(binary) => float}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{"1.0" => 1.0, 2 => 2.0},
                 quote(do: %{required(integer) => float, required(binary) => float}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{:foo => 1},
                 quote(do: %{optional(atom) => integer}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{},
                 quote(do: %{optional(atom) => integer}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{:one => 1, 1.0 => 1},
                 quote(do: %{optional(atom) => integer, required(float) => integer}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{1.0 => 1},
                 quote(do: %{optional(atom) => integer, required(float) => integer}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{:one => 1, 1.0 => 1},
                 quote(do: %{required(atom) => integer, optional(any) => any}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{:foo => :bar, "one" => 1.0},
                 quote(do: %{optional(any) => any}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(%{}, quote(do: %{optional(any) => any}), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %{:foo => :bar, "one" => 1.0},
                 quote(do: map),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(%{}, quote(do: map), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %{"any" => 1.0},
                 quote(do: %{required(any) => float}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{:foo => :bar},
                 quote(do: %{required(atom) => atom, required(atom) => integer}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %{"any" => 1.0, :any => 1},
                 quote(do: %{required(binary | atom) => integer | float}),
                 TypeList.env()
               )

      assert true == TypeContract.valid?(%{}, quote(do: integer | map), TypeList.env())

      assert false == TypeContract.valid?(%{one: 1}, quote(do: %{}), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 %{one: :atom, two: 1.0},
                 quote(do: %{one: integer, two: float}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{one: 1, eh: 1.0},
                 quote(do: %{one: integer, two: float}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{},
                 quote(do: %{one: integer, two: float}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{1.0 => 1.0},
                 quote(do: %{required(binary) => float}),
                 TypeList.env()
               )

      # The following assertion is oposite to the dialyzer v4.1.1 behaviour
      assert false ==
               TypeContract.valid?(
                 %{},
                 quote(do: %{required(binary) => float}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{"1" => 1.0, 1 => 1},
                 quote(do: %{required(atom) => atom, required(binary) => float}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{:one => 1, 1 => 1},
                 quote(do: %{optional(atom) => integer}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{:one => 1, 1.0 => 1, 2.0 => :two},
                 quote(do: %{required(float) => integer, optional(atom) => integer}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{:one => 1},
                 quote(do: %{required(float) => integer, optional(atom) => integer}),
                 TypeList.env()
               )

      # The following assertion is opposite to the dialyzer v4.1.1 behaviour.
      assert false ==
               TypeContract.valid?(
                 %{},
                 quote(do: %{required(atom) => integer, optional(any) => any}),
                 TypeList.env()
               )

      # The following assertion is opposite to the dialyzer v4.1.1 behaviour.
      assert false ==
               TypeContract.valid?(
                 %{"some" => "str"},
                 quote(do: %{required(atom) => integer, optional(any) => any}),
                 TypeList.env()
               )

      # The following assertion is opposite to the dialyzer v4.1.1 behaviour.
      assert false ==
               TypeContract.valid?(%{}, quote(do: %{required(any) => any}), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 %{:foo => 1},
                 quote(do: %{required(atom) => atom, required(atom) => integer}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{1.0 => 1, :two => :two},
                 quote(
                   do:
                     @type(%{
                       required(float) => integer,
                       optional(atom) => integer,
                       optional(atom) => atom
                     })
                 ),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(
                 %{1 => 1.0, :any => 1},
                 quote(do: %{required(binary | atom) => integer | float}),
                 TypeList.env()
               )

      assert false == TypeContract.valid?(%{}, quote(do: integer | atom), TypeList.env())
    end

    test "validatable for struct" do
      assert true ==
               TypeContract.valid?(%CustomStruct{}, quote(do: %CustomStruct{}), TypeList.env())

      assert true == TypeContract.valid?(%CustomStruct{}, quote(do: map), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %CustomStruct{title: 1},
                 quote(do: %CustomStruct{}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(
                 %CustomStruct{title: 1.0},
                 quote(do: %CustomStruct{title: float}),
                 TypeList.env()
               )

      assert true ==
               TypeContract.valid?(%CustomStruct{title: 1.0}, quote(do: struct), TypeList.env())

      assert true ==
               TypeContract.valid?(
                 %CustomStruct{title: 1.0},
                 quote(do: atom | struct),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(%CustomStruct{}, quote(do: %UndefStruct{}), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 %CustomStruct{title: 1},
                 quote(do: %CustomStruct{title: float}),
                 TypeList.env()
               )

      assert false ==
               TypeContract.valid?(%{}, quote(do: %CustomStruct{title: float}), TypeList.env())

      assert false ==
               TypeContract.valid?(
                 %CustomStruct{title: 1.0},
                 quote(do: atom | integer),
                 TypeList.env()
               )
    end
  end
end
