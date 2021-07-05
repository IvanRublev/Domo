defmodule Domo.TypeEnsurerFactory.GeneratorTypeEnsurerModuleTest do
  use Domo.FileCase, async: false

  import GeneratorTestHelper

  alias Domo.ErrorBuilder
  alias Domo.TypeEnsurerFactory.Precondition
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  setup_all do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(tmp_path())

    on_exit(fn ->
      File.rm_rf(tmp_path())
      Code.compiler_options(ignore_module_conflict: false)
    end)

    # Evaluate modules to prepare plan file for domo mix task
    Code.eval_file("test/support/empty_struct.ex")
    Code.eval_file("test/support/custom_struct.ex")

    {:ok, []} = DomoMixTask.run([])
  end

  setup do
    on_exit(fn ->
      :code.purge(TypeEnsurer)
      :code.delete(TypeEnsurer)
    end)

    :ok
  end

  def call_ensure_field_type({_field, _value} = subject) do
    apply(TypeEnsurer, :ensure_field_type, [subject])
  end

  def call_t_precondition(subject) do
    apply(TypeEnsurer, :t_precondition, [subject])
  end

  def call_pretty_error({:error, _} = error) do
    apply(ErrorBuilder, :pretty_error, [error])
  end

  def call_pretty_error_by_key({:error, _} = error) do
    apply(ErrorBuilder, :pretty_error_by_key, [error])
  end

  describe "Generated TypeEnsurer module" do
    test "has ensure_field_type/1 function for each field" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: integer())],
        second: [quote(do: integer())]
      })

      call_ensure_field_type({:first, 1})
      call_ensure_field_type({:second, 2})
    end

    test "has ensure_t_precondition/1 function" do
      precondition = Precondition.new(module: UserTypes, type_name: :t, description: "t_func")

      load_type_ensurer_module(
        {%{
           first: [{quote(do: integer()), nil}],
           second: [{quote(do: integer()), nil}]
         }, precondition}
      )

      call_t_precondition(%{first: 1, second: 2})
    end

    test "has No ensure_type function matching unspecified field" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: integer())]})

      assert_raise FunctionClauseError, ~r/no function/, fn ->
        call_ensure_field_type({:second, :atom})
      end
    end

    test "has pretty_error function returning :error tuple with human readable message" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: integer())]})

      error =
        {:error,
         {
           :type_mismatch,
           :a_struct_module,
           :a_key,
           :wrong_value,
           [:float],
           [{"hello %{value}", [value: "world"]}, {"other", []}]
         }}

      assert """
             Invalid value :wrong_value for field :a_key of %:a_struct_module{}. Expected the value matching the float type.
             Underlying errors:
                - hello world
                - other\
             """ == call_pretty_error(error)
    end

    test "has pretty_error_by_key function returning a tuple with key and human readable error" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: integer())]})

      error =
        {:error,
         {
           :type_mismatch,
           :a_struct_module,
           :a_key,
           :wrong_value,
           ["float()"],
           [{"hello %{value}", [value: "world"]}, {"other", []}]
         }}

      assert {:a_key,
              """
              Invalid value :wrong_value for field :a_key of %:a_struct_module{}. Expected the value matching the float() type.
              Underlying errors:
                 - hello world
                 - other\
              """} == call_pretty_error_by_key(error)
    end

    test "returns :error giving t precondition false result" do
      precondition = Precondition.new(module: UserTypes, type_name: :t, description: "t_func")

      load_type_ensurer_module({
        %{
          first: [{quote(do: integer()), nil}],
          second: [{quote(do: integer()), nil}]
        },
        precondition
      })

      response = call_t_precondition(%{first: 1, second: 2})
      assert {:error, _} = response

      assert """
             Invalid value %{first: 1, second: 2}. Expected the value matching the Elixir.t() type. \
             And a true value from the precondition function \"t_func\" defined for UserTypes.t() type.\
             """ == call_pretty_error(response)
    end

    test "returns :ok when t precondition function freturns true" do
      precondition = Precondition.new(module: UserTypes, type_name: :t, description: "t_func")

      load_type_ensurer_module({
        %{
          first: [{quote(do: integer()), nil}],
          second: [{quote(do: integer()), nil}]
        },
        precondition
      })

      assert :ok = call_t_precondition(%{first: 10, second: 2})
    end

    test "returns :error when value mismatches the type" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: integer())]})

      response = call_ensure_field_type({:first, "one"})

      assert {:error, _} = response

      assert "Invalid value \"one\" for field :first of %Elixir{}. Expected the value matching the integer() type." ==
               call_pretty_error(response)
    end

    test "returns :error when value matches type and precondition returns false" do
      precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")
      load_type_ensurer_module({%{first: [{quote(do: integer()), precondition}]}, nil})

      response = call_ensure_field_type({:first, -1})

      assert {:error, _} = response

      assert """
             Invalid value -1 for field :first of %Elixir{}. Expected the value matching the integer() type. \
             And a true value from the precondition function \"positive_integer_func\" defined \
             for UserTypes.positive_integer() type.\
             """ == call_pretty_error(response)
    end

    test "returns :error when deeply nested value matches type and precondition returns false" do
      int_precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")
      tuple_precondition = Precondition.new(module: UserTypes, type_name: :first_elem_gt_5, description: "first_elem_gt_5_func")

      load_type_ensurer_module({
        %{
          first: [
            {
              {{quote(do: integer()), nil}, {quote(do: integer()), int_precondition}},
              tuple_precondition
            }
          ]
        },
        nil
      })

      response = call_ensure_field_type({:first, {0, -1}})
      assert {:error, _} = response

      assert """
             Invalid value {0, -1} for field :first of %Elixir{}. Expected the value matching the {integer(), integer()} type.
             Underlying errors:
                - The element at index 1 has value -1 that is invalid.
                - Expected the value matching the integer() type. And a true value from the precondition \
             function "positive_integer_func" defined for UserTypes.positive_integer() type.\
             """ == call_pretty_error(response)
    end

    test "returns :ok when field value matches the specified type" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: integer())]})
      assert :ok == call_ensure_field_type({:first, 1})
    end

    test "returns :ok when value matches type and precondition returns true" do
      precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")
      load_type_ensurer_module({%{first: [{quote(do: integer()), precondition}]}, nil})
      assert :ok == call_ensure_field_type({:first, 1})
    end

    test "returns :ok when field value matches one of the specified types" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: integer()), quote(do: atom())]
      })

      assert :ok == call_ensure_field_type({:first, 1})
      assert :ok == call_ensure_field_type({:first, :one})
    end

    test "return :ok when one of preconditions return true for field value" do
      precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")

      load_type_ensurer_module({
        %{first: [{quote(do: integer()), precondition}, {quote(do: atom()), nil}]},
        nil
      })

      assert :ok == call_ensure_field_type({:first, 1})
      assert :ok == call_ensure_field_type({:first, :one})
    end

    test "returns :error when value doesn't match any of types specified" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: integer()), quote(do: atom())]
      })

      response = call_ensure_field_type({:first, "one"})

      assert {:error, _} = response

      assert """
             Invalid value "one" for field :first of %Elixir{}. Expected the value matching the integer() | atom() type.\
             """ == call_pretty_error(response)
    end

    test "returns :error when value matches one of types and its precondition returns false" do
      precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")

      load_type_ensurer_module({
        %{first: [{quote(do: integer()), precondition}, {quote(do: atom()), nil}]},
        nil
      })

      response = call_ensure_field_type({:first, -1})

      assert {:error, _} = response

      assert """
             Invalid value -1 for field :first of %Elixir{}. Expected the value matching the integer() | atom() type.
             Underlying errors:
                - Expected the value matching the integer() type. And a true value from the precondition function \"positive_integer_func\" defined \
             for UserTypes.positive_integer() type.\
             """ == call_pretty_error(response)
    end
  end

  describe "Generated TypeEnsurer module verifies literal / basic type" do
    test "any" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: any())],
        second: [quote(do: atom()), quote(do: any())],
        third: [quote(do: term())]
      })

      assert :ok == call_ensure_field_type({:first, 12_345})
      assert :ok == call_ensure_field_type({:first, "anything"})
      assert :ok == call_ensure_field_type({:first, :anything})

      assert :ok == call_ensure_field_type({:second, 12_345})
      assert :ok == call_ensure_field_type({:second, "anything"})
      assert :ok == call_ensure_field_type({:second, :anything})

      assert :ok == call_ensure_field_type({:third, 12_345})
      assert :ok == call_ensure_field_type({:third, "anything"})
      assert :ok == call_ensure_field_type({:third, :anything})
    end

    test "atom" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: atom())],
        second: [quote(do: :some_atom)],
        third: [quote(do: true)],
        forth: [quote(do: false)],
        fifth: [quote(do: nil)]
      })

      assert :ok == call_ensure_field_type({:first, :anything})
      assert {:error, _} = call_ensure_field_type({:first, "anything"})

      assert :ok == call_ensure_field_type({:second, :some_atom})
      assert {:error, _} = call_ensure_field_type({:second, :other_atom})
      assert {:error, _} = call_ensure_field_type({:second, "not_an_atom"})

      assert :ok == call_ensure_field_type({:third, true})
      assert {:error, _} = call_ensure_field_type({:third, false})
      assert {:error, _} = call_ensure_field_type({:third, "not_a_bool"})

      assert :ok == call_ensure_field_type({:forth, false})
      assert {:error, _} = call_ensure_field_type({:forth, true})
      assert {:error, _} = call_ensure_field_type({:forth, :not_a_bool})

      assert :ok == call_ensure_field_type({:fifth, nil})
      assert {:error, _} = call_ensure_field_type({:fifth, "not a nil"})
    end

    test "empty map" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: map())],
        second: [quote(do: %{})]
      })

      assert :ok == call_ensure_field_type({:first, %{}})
      assert :ok == call_ensure_field_type({:first, %{one: 1}})
      assert :ok == call_ensure_field_type({:first, %EmptyStruct{}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_map})

      assert :ok == call_ensure_field_type({:second, %{}})
      assert {:error, _} = call_ensure_field_type({:second, %{one: 1}})
      assert {:error, _} = call_ensure_field_type({:second, %EmptyStruct{}})
      assert {:error, _} = call_ensure_field_type({:second, :not_a_map})
    end

    test "pid" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: pid())]})

      assert :ok == call_ensure_field_type({:first, self()})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_pid})
    end

    test "port" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: port())]})

      assert :ok == call_ensure_field_type({:first, :erlang.list_to_port('#Port<0.0>')})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_port})
    end

    test "reference" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: reference())]})

      assert :ok == call_ensure_field_type({:first, :erlang.list_to_ref('#Ref<0.0.0.0>')})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_ref})
    end

    test "any or empty tuple" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: tuple())],
        second: [quote(do: {})]
      })

      assert :ok == call_ensure_field_type({:first, {}})
      assert :ok == call_ensure_field_type({:first, {1.0}})
      assert :ok == call_ensure_field_type({:first, {1, :two, {"three"}}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_tuple})

      assert :ok == call_ensure_field_type({:second, {}})
      assert {:error, _} = call_ensure_field_type({:second, {1}})
      assert {:error, _} = call_ensure_field_type({:second, :not_a_tuple})
    end

    test "float" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: float())]})

      assert :ok == call_ensure_field_type({:first, 0.0})
      assert :ok == call_ensure_field_type({:first, 1.0})
      assert {:error, _} = call_ensure_field_type({:first, 0})
      assert {:error, _} = call_ensure_field_type({:first, 1})
    end

    test "precondition for float" do
      precondition = Precondition.new(module: UserTypes, type_name: :positive_float, description: "positive_float_func")

      load_type_ensurer_module({%{first: [{quote(do: float()), precondition}]}, nil})

      assert :ok == call_ensure_field_type({:first, 1.2})
      assert {:error, _} = call_ensure_field_type({:first, 1.0})
    end

    test "integer" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: integer())],
        second: [quote(do: 5)],
        second_half: [quote(do: -5)],
        third: [quote(do: 3..8)],
        third_half: [quote(do: -8..-3)],
        forth: [quote(do: neg_integer())],
        fifth: [quote(do: non_neg_integer())],
        sixth: [quote(do: pos_integer())]
      })

      assert :ok == call_ensure_field_type({:first, 0})
      assert :ok == call_ensure_field_type({:first, 1})
      assert {:error, _} = call_ensure_field_type({:first, 0.0})
      assert {:error, _} = call_ensure_field_type({:first, 1.0})

      assert :ok == call_ensure_field_type({:second, 5})
      assert {:error, _} = call_ensure_field_type({:second, 6})
      assert {:error, _} = call_ensure_field_type({:second, :not_an_integer})

      assert :ok == call_ensure_field_type({:second_half, -5})
      assert {:error, _} = call_ensure_field_type({:second_half, -6})
      assert {:error, _} = call_ensure_field_type({:second_half, :not_an_integer})

      assert :ok == call_ensure_field_type({:third, 3})
      assert :ok == call_ensure_field_type({:third, 6})
      assert :ok == call_ensure_field_type({:third, 8})
      assert {:error, _} = call_ensure_field_type({:third, 2})
      assert {:error, _} = call_ensure_field_type({:third, 9})
      assert {:error, _} = call_ensure_field_type({:third, :not_an_integer})

      assert :ok == call_ensure_field_type({:third_half, -3})
      assert :ok == call_ensure_field_type({:third_half, -6})
      assert :ok == call_ensure_field_type({:third_half, -8})
      assert {:error, _} = call_ensure_field_type({:third_half, -2})
      assert {:error, _} = call_ensure_field_type({:third_half, -9})
      assert {:error, _} = call_ensure_field_type({:third_half, :not_an_integer})

      assert :ok == call_ensure_field_type({:forth, -5})
      assert :ok == call_ensure_field_type({:forth, -1})
      assert {:error, _} = call_ensure_field_type({:forth, 0})
      assert {:error, _} = call_ensure_field_type({:forth, 1})
      assert {:error, _} = call_ensure_field_type({:forth, :not_an_integer})

      assert :ok == call_ensure_field_type({:fifth, 0})
      assert :ok == call_ensure_field_type({:fifth, 1})
      assert {:error, _} = call_ensure_field_type({:fifth, -1})
      assert {:error, _} = call_ensure_field_type({:fifth, :not_an_integer})

      assert :ok == call_ensure_field_type({:sixth, 1})
      assert {:error, _} = call_ensure_field_type({:sixth, 0})
      assert {:error, _} = call_ensure_field_type({:sixth, :not_an_integer})
    end

    test "precondition for binary" do
      precondition = Precondition.new(module: UserTypes, type_name: :binary_6, description: "binary_6_func")

      load_type_ensurer_module({%{first: [{quote(do: <<_::_*8>>), precondition}]}, nil})

      assert :ok == call_ensure_field_type({:first, "hello!"})
      assert {:error, _} = call_ensure_field_type({:first, 1.0})
      assert {:error, _} = call_ensure_field_type({:first, "h"})
    end

    test "bitstring" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: <<>>)],
        second: [quote(do: <<_::0>>)],
        third: [quote(do: <<_::9>>)],
        # sequence of k*3 bits
        forth: [quote(do: <<_::_*3>>)],
        # sequense of n + (k*4) bits
        fifth: [quote(do: <<_::0, _::_*4>>)],
        sixth: [quote(do: <<_::5, _::_*4>>)]
      })

      assert :ok == call_ensure_field_type({:first, ""})
      assert {:error, _} = call_ensure_field_type({:first, "a"})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_binary})

      assert :ok == call_ensure_field_type({:second, <<0::size(0)>>})
      assert {:error, _} = call_ensure_field_type({:second, <<0::size(1)>>})
      assert {:error, _} = call_ensure_field_type({:second, :not_a_binary})

      assert :ok == call_ensure_field_type({:third, <<0::size(9)>>})
      assert {:error, _} = call_ensure_field_type({:third, <<0::size(8)>>})
      assert {:error, _} = call_ensure_field_type({:third, <<0::size(10)>>})
      assert {:error, _} = call_ensure_field_type({:third, :not_a_binary})

      assert :ok == call_ensure_field_type({:forth, <<0::size(3)>>})
      assert :ok == call_ensure_field_type({:forth, <<0::size(6)>>})
      assert :ok == call_ensure_field_type({:forth, <<0::size(9)>>})
      assert {:error, _} = call_ensure_field_type({:forth, <<0::size(2)>>})
      assert {:error, _} = call_ensure_field_type({:forth, <<0::size(7)>>})
      assert {:error, _} = call_ensure_field_type({:forth, <<0::size(10)>>})
      assert {:error, _} = call_ensure_field_type({:forth, :not_a_binary})

      assert :ok == call_ensure_field_type({:fifth, <<0::size(4)>>})
      assert :ok == call_ensure_field_type({:fifth, <<0::size(8)>>})
      assert {:error, _} = call_ensure_field_type({:fifth, <<0::size(3)>>})
      assert {:error, _} = call_ensure_field_type({:fifth, <<0::size(5)>>})
      assert {:error, _} = call_ensure_field_type({:fifth, <<0::size(9)>>})
      assert {:error, _} = call_ensure_field_type({:fifth, :not_a_binary})

      assert :ok == call_ensure_field_type({:sixth, <<0::size(9)>>})
      assert :ok == call_ensure_field_type({:sixth, <<0::size(13)>>})
      assert :ok == call_ensure_field_type({:sixth, <<0::size(17)>>})
      assert {:error, _} = call_ensure_field_type({:sixth, <<0::size(8)>>})
      assert {:error, _} = call_ensure_field_type({:sixth, <<0::size(12)>>})
      assert {:error, _} = call_ensure_field_type({:sixth, <<0::size(14)>>})
      assert {:error, _} = call_ensure_field_type({:sixth, :not_a_binary})
    end

    test "function" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: (() -> any()))],
        second: [quote(do: (... -> any()))]
      })

      # check that the value is a function, don't check arity or return type
      assert :ok == call_ensure_field_type({:first, fn -> nil end})
      assert :ok = call_ensure_field_type({:first, fn _arg -> nil end})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_function})

      assert :ok == call_ensure_field_type({:second, fn -> nil end})
      assert :ok = call_ensure_field_type({:second, fn _arg -> nil end})
      assert {:error, _} = call_ensure_field_type({:second, :not_a_function})
    end

    test "empty list" do
      load_type_ensurer_module_with_no_preconds(%{first: [quote(do: [])]})

      assert :ok == call_ensure_field_type({:first, []})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_function})
    end

    test "empty struct" do
      defmodule EmptyStruct1 do
        defstruct []
        @type t :: %__MODULE__{}
      end

      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %EmptyStruct{})]
      })

      assert :ok == call_ensure_field_type({:first, %EmptyStruct{}})
      assert {:error, _} = call_ensure_field_type({:first, struct(EmptyStruct1)})
      assert {:error, _} = call_ensure_field_type({:first, %{}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_struct})
    end
  end

  describe "Generated TypeEnsurer module verifies Kernel struct type" do
    test "MapSet with no precondition" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %MapSet{})]
      })

      assert :ok == call_ensure_field_type({:first, MapSet.new()})
      assert :ok == call_ensure_field_type({:first, MapSet.new([:one])})
      assert :ok == call_ensure_field_type({:first, MapSet.new([:one, :two, :three])})
      assert {:error, _} = call_ensure_field_type({:first, [:one]})
      assert {:error, _} = call_ensure_field_type({:first, %{one: 1}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_map_set})
    end

    test "MapSet with precondition" do
      precondition = Precondition.new(module: UserTypes, type_name: :map_set_only_floats, description: "map_set_only_floats")

      load_type_ensurer_module({%{first: [{quote(do: %MapSet{}), precondition}]}, nil})

      assert :ok == call_ensure_field_type({:first, MapSet.new([3.2, 0.0, 1.0])})
      assert {:error, _} = call_ensure_field_type({:first, MapSet.new([3.2, 1])})
      assert {:error, _} = call_ensure_field_type({:first, "h"})
    end

    test "Range.t() with no precondition" do
      load_type_ensurer_module_with_no_preconds(
        case ElixirVersion.version() do
          [1, minor, _] when minor < 12 ->
            %{first: [quote(context: Range, do: %Range{first: integer(), last: integer()})]}

          [1, minor, _] when minor >= 12 ->
            %{
              first: [
                quote(context: Range, do: %Range{first: integer(), last: integer(), step: pos_integer()}),
                quote(context: Range, do: %Range{first: integer(), last: integer(), step: neg_integer()})
              ]
            }
        end
      )

      assert :ok == call_ensure_field_type({:first, 1..3})
      assert :ok == call_ensure_field_type({:first, 3..1})
      assert :ok == call_ensure_field_type({:first, -5..2})
      assert {:error, _} = call_ensure_field_type({:first, [:one]})
      assert {:error, _} = call_ensure_field_type({:first, %{one: 1}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_range})
    end

    test "Range.t() with precondition" do
      precondition = Precondition.new(module: UserTypes, type_name: :inner_range_5_8, description: "inner_range")

      load_type_ensurer_module(
        case ElixirVersion.version() do
          [1, minor, _] when minor < 12 ->
            {%{first: [{quote(context: Range, do: %Range{first: integer(), last: integer()}), precondition}]}, nil}

          [1, minor, _] when minor >= 12 ->
            {%{
               first: [
                 {quote(context: Range, do: %Range{first: integer(), last: integer(), step: pos_integer()}), precondition},
                 {quote(context: Range, do: %Range{first: integer(), last: integer(), step: neg_integer()}), precondition}
               ]
             }, nil}
        end
      )

      assert :ok == call_ensure_field_type({:first, 6..7})
      assert :ok == call_ensure_field_type({:first, 7..6})
      assert :ok == call_ensure_field_type({:first, 7..7})
      assert {:error, _} = call_ensure_field_type({:first, 5..7})
      assert {:error, _} = call_ensure_field_type({:first, 0..2})
      assert {:error, _} = call_ensure_field_type({:first, 9..7})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_range})
    end
  end

  describe "Generated TypeEnsurer module verifies basic/listeral typed" do
    test "proper [t]" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: [atom()])]
      })

      assert :ok == call_ensure_field_type({:first, []})
      assert :ok == call_ensure_field_type({:first, [:one]})
      assert :ok == call_ensure_field_type({:first, [:one, :two, :three]})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, [:one | 1]})
      assert {:error, _} = call_ensure_field_type({:first, [:one | :two]})
      assert {:error, _} = call_ensure_field_type({:first, [:first, :second, "third", :forth]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_list})
    end

    test "nonempty_list(t)" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: nonempty_list(atom()))]
      })

      assert :ok == call_ensure_field_type({:first, [:one]})
      assert :ok == call_ensure_field_type({:first, [:one, :two, :three]})
      assert {:error, _} = call_ensure_field_type({:first, []})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, [:one | 1]})
      assert {:error, _} = call_ensure_field_type({:first, [:first, :second, "third", :forth]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_list})
    end

    test "maybe_improper_list(t1, t2)" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: maybe_improper_list(atom(), integer()))]
      })

      assert :ok == call_ensure_field_type({:first, []})
      assert :ok == call_ensure_field_type({:first, [:one]})
      assert :ok == call_ensure_field_type({:first, [:one, :two, :three]})
      assert :ok == call_ensure_field_type({:first, [:one | 1]})
      assert :ok == call_ensure_field_type({:first, [:one, :two | 1]})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_list})
      assert {:error, _} = call_ensure_field_type({:first, [:one | :one]})
    end

    test "nonempty_improper_list(t1, t2)" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: nonempty_improper_list(atom(), integer()))]
      })

      assert :ok == call_ensure_field_type({:first, [:one | 1]})
      assert :ok == call_ensure_field_type({:first, [:one, :two | 1]})
      assert {:error, _} = call_ensure_field_type({:first, []})
      assert {:error, _} = call_ensure_field_type({:first, [:one]})
      assert {:error, _} = call_ensure_field_type({:first, [:one, :two, :three]})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_list})
      assert {:error, _} = call_ensure_field_type({:first, [:one | :one]})
    end

    test "nonempty_maybe_improper_list(t1, t2)" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: nonempty_maybe_improper_list(atom(), integer()))]
      })

      assert {:error, _} = call_ensure_field_type({:first, []})
      assert :ok == call_ensure_field_type({:first, [:one]})
      assert :ok == call_ensure_field_type({:first, [:one, :two, :three]})
      assert :ok == call_ensure_field_type({:first, [:one | 1]})
      assert :ok == call_ensure_field_type({:first, [:one, :two | 1]})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_list})
      assert {:error, _} = call_ensure_field_type({:first, [:one | :one]})
    end

    test "two proper and two improper lists aside without functions clashes" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: [atom()])],
        second: [quote(do: [integer()])],
        third: [quote(do: nonempty_improper_list(atom(), integer()))],
        forth: [quote(do: nonempty_improper_list(integer(), atom()))]
      })

      assert :ok == call_ensure_field_type({:first, [:one]})
      assert :ok == call_ensure_field_type({:second, [1]})
      assert :ok == call_ensure_field_type({:third, [:one | 1]})
      assert :ok == call_ensure_field_type({:forth, [1 | :one]})
    end

    test "precondition for lists" do
      list_precondition = Precondition.new(module: UserTypes, type_name: :hd_gt_7, description: "hd_gt_7_func")
      int_precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")
      float_precondition = Precondition.new(module: UserTypes, type_name: :positive_float, description: "positive_float_func")

      load_type_ensurer_module(
        {%{
           first: [
             {[quote(do: {integer(), unquote(int_precondition)})], list_precondition}
           ],
           second: [
             {quote(do: maybe_improper_list({integer(), unquote(int_precondition)}, {float(), unquote(float_precondition)})), list_precondition}
           ],
           third: [
             {quote(do: nonempty_improper_list({integer(), unquote(int_precondition)}, {float(), unquote(float_precondition)})), list_precondition}
           ],
           fourth: [
             {quote(do: nonempty_maybe_improper_list({integer(), unquote(int_precondition)}, {float(), unquote(float_precondition)})),
              list_precondition}
           ]
         }, nil}
      )

      assert :ok == call_ensure_field_type({:first, [8]})
      assert :ok == call_ensure_field_type({:second, [8 | 1.2]})
      assert :ok == call_ensure_field_type({:third, [8 | 1.2]})
      assert :ok == call_ensure_field_type({:fourth, [8 | 1.2]})
      assert :ok == call_ensure_field_type({:fourth, [8]})

      assert {:error, _} = call_ensure_field_type({:first, [-1]})
      assert {:error, _} = call_ensure_field_type({:second, [-1 | 1.2]})
      assert {:error, _} = call_ensure_field_type({:second, [8 | 1.0]})
      assert {:error, _} = call_ensure_field_type({:third, [-1 | 1.2]})
      assert {:error, _} = call_ensure_field_type({:third, [8 | 1.0]})
      assert {:error, _} = call_ensure_field_type({:fourth, [-1 | 1.2]})
      assert {:error, _} = call_ensure_field_type({:fourth, [8 | 1.0]})
      assert {:error, _} = call_ensure_field_type({:fourth, [-1]})

      assert {:error, _} = call_ensure_field_type({:first, [6]})
      assert {:error, _} = call_ensure_field_type({:second, [6 | 1.2]})
      assert {:error, _} = call_ensure_field_type({:third, [6 | 1.2]})
      assert {:error, _} = call_ensure_field_type({:fourth, [6 | 1.2]})
      assert {:error, _} = call_ensure_field_type({:fourth, [6]})
    end
  end

  describe "Generated TypeEnsurer module verifies basic/listeral typed tuples of" do
    test "one element" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: {atom()})]
      })

      assert :ok == call_ensure_field_type({:first, {:one}})
      assert {:error, _} = call_ensure_field_type({:first, {}})
      assert {:error, _} = call_ensure_field_type({:first, {:one, :two, :three}})
      assert {:error, _} = call_ensure_field_type({:first, {1}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_tuple})
    end

    test "two element" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: {atom(), integer()})]
      })

      assert :ok == call_ensure_field_type({:first, {:one, 1}})
      assert {:error, _} = call_ensure_field_type({:first, {:one, :two}})
      assert {:error, _} = call_ensure_field_type({:first, {1, 2}})
      assert {:error, _} = call_ensure_field_type({:first, {}})
      assert {:error, _} = call_ensure_field_type({:first, {:one, :two, :three}})
      assert {:error, _} = call_ensure_field_type({:first, {:one, 1, 2}})
      assert {:error, _} = call_ensure_field_type({:first, {1}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_tuple})
    end

    test "many elements" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: {atom(), integer(), :third, float(), 5})]
      })

      assert :ok == call_ensure_field_type({:first, {:first, 2, :third, 4.0, 5}})
      assert {:error, _} = call_ensure_field_type({:first, {:first, 2, 3, 4.0, 5}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_tuple})
    end

    test "precondition for 1, 2, 3 or any number of elements tuple" do
      precondition = Precondition.new(module: UserTypes, type_name: :first_elem_gt_5, description: "first_elem_gt_5_func")

      load_type_ensurer_module(
        {%{
           first: [{quote(do: {{integer(), nil}}), precondition}],
           second: [{quote(do: {{integer(), nil}, {integer(), nil}}), precondition}],
           third: [{quote(do: {{integer(), nil}, {integer(), nil}, {integer(), nil}}), precondition}],
           fourth: [{quote(do: tuple()), precondition}]
         }, nil}
      )

      assert :ok == call_ensure_field_type({:first, {6}})
      assert :ok == call_ensure_field_type({:second, {6, 0}})
      assert :ok == call_ensure_field_type({:third, {6, 0, 0}})
      assert :ok == call_ensure_field_type({:fourth, {6, 0, 0, 0}})

      assert {:error, _} = call_ensure_field_type({:first, {}})
      assert {:error, _} = call_ensure_field_type({:second, {7}})
      assert {:error, _} = call_ensure_field_type({:third, {7, 8}})
      assert {:error, _} = call_ensure_field_type({:fourth, :not_a_tuple})

      assert {:error, _} = call_ensure_field_type({:first, {0}})
      assert {:error, _} = call_ensure_field_type({:second, {0, 0}})
      assert {:error, _} = call_ensure_field_type({:third, {0, 0, 0}})
      assert {:error, _} = call_ensure_field_type({:fourth, {0, 0, 0, 0}})
    end
  end

  describe "Generated TypeEnsurer module verifies basic/listeral typed maps of" do
    test "given keys and value types" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %{former: atom()})],
        second: [quote(do: %{atom: atom(), integer: integer(), float: float()})]
      })

      assert :ok == call_ensure_field_type({:first, %{former: :one}})
      assert {:error, _} = call_ensure_field_type({:first, %{former: :one, latter: 2}})
      assert {:error, _} = call_ensure_field_type({:first, %{former: 1}})
      assert {:error, _} = call_ensure_field_type({:first, %{}})
      assert {:error, _} = call_ensure_field_type({:first, %{latter: 2}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_map})

      assert :ok == call_ensure_field_type({:second, %{atom: :one, integer: 1, float: 0.5}})
      assert {:error, _} = call_ensure_field_type({:second, %{atom: :one, integer: 1, float: 5}})
    end

    test "required key type and value type" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %{required(float()) => atom()})],
        second: [quote(do: %{required(atom()) => atom(), required(integer()) => float()})]
      })

      assert :ok == call_ensure_field_type({:first, %{0.5 => :one}})
      assert :ok == call_ensure_field_type({:first, %{0.5 => :one, 0.6 => :two, 0.7 => :three}})
      assert {:error, _} = call_ensure_field_type({:first, %{0.5 => :one, latter: 2}})
      assert {:error, _} = call_ensure_field_type({:first, %{5 => :one}})
      assert {:error, _} = call_ensure_field_type({:first, %{0.5 => 1}})
      assert {:error, _} = call_ensure_field_type({:first, %{}})
      assert {:error, _} = call_ensure_field_type({:first, %{latter: 2}})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_map})

      assert :ok == call_ensure_field_type({:second, %{:one => :one, 1 => 1.0}})
      assert :ok == call_ensure_field_type({:second, %{:one => :one, :two => :two, 1 => 1.0}})
      assert {:error, _} = call_ensure_field_type({:second, %{:one => :one}})
      assert {:error, _} = call_ensure_field_type({:second, %{1 => 1.0}})
      assert {:error, _} = call_ensure_field_type({:second, %{:one => 1.0, 1 => :one}})
    end

    test "optional key type and value type" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %{optional(integer) => atom})]
      })

      assert :ok == call_ensure_field_type({:first, %{}})
      assert :ok == call_ensure_field_type({:first, %{1 => :one}})
      assert :ok == call_ensure_field_type({:first, %{1 => :one, 2 => :two}})
      assert {:error, _} = call_ensure_field_type({:first, %{0.5 => 1}})
      assert {:error, _} = call_ensure_field_type({:first, %{1 => :one, "two" => :two}})
    end

    test "mixed required and optional key and value types" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %{required(float) => atom, optional(integer) => atom})]
      })

      assert :ok == call_ensure_field_type({:first, %{1.0 => :one}})
      assert :ok == call_ensure_field_type({:first, %{1.0 => :one, 1 => :one}})

      assert {:error, _} = call_ensure_field_type({:first, %{1.0 => :one, 1 => :one, 2 => :two, "three" => 3}})

      assert {:error, _} = call_ensure_field_type({:first, %{}})
      assert {:error, _} = call_ensure_field_type({:first, %{0.5 => 1}})
      assert {:error, _} = call_ensure_field_type({:first, %{1 => :one, "two" => :two}})
    end

    test "required, optional with preconditions" do
      map_precondition = Precondition.new(module: UserTypes, type_name: :map_value_sum_2_4, description: "map_value_sum_2_4_func")
      int_precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")
      float_precondition = Precondition.new(module: UserTypes, type_name: :positive_float, description: "positive_float_func")

      load_type_ensurer_module(
        {%{
           first: [
             {
               quote do
                 %{
                   integer: {integer(), unquote(int_precondition)},
                   float: {float(), unquote(float_precondition)}
                 }
               end,
               map_precondition
             }
           ],
           second: [
             {
               quote do
                 %{
                   required({float(), unquote(float_precondition)}) => {integer(), unquote(int_precondition)},
                   optional({integer(), unquote(int_precondition)}) => {float(), unquote(float_precondition)}
                 }
               end,
               map_precondition
             }
           ]
         }, nil}
      )

      assert :ok == call_ensure_field_type({:first, %{integer: 2, float: 1.2}})
      assert :ok == call_ensure_field_type({:second, %{1.2 => 1, 2 => 2.0}})

      assert {:error, _} = call_ensure_field_type({:first, %{integer: 1, float: 1.2}})
      assert {:error, _} = call_ensure_field_type({:second, %{1.2 => 1, 2 => 1.2}})

      assert {:error, _} = call_ensure_field_type({:first, %{integer: 0, float: 1.2}})
      assert {:error, _} = call_ensure_field_type({:first, %{integer: 1, float: 1.0}})
      assert {:error, _} = call_ensure_field_type({:second, %{1.2 => 0, 2 => 2.0}})
      assert {:error, _} = call_ensure_field_type({:second, %{1.2 => 1, 2 => 1.0}})
    end
  end

  describe "Generator should make a module for basic/literal typed keyword list that" do
    test "verifies value with no precondition" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: [key1: atom(), key2: integer()])]
      })

      assert :ok == call_ensure_field_type({:first, []})
      assert :ok == call_ensure_field_type({:first, [key1: :one]})
      assert :ok == call_ensure_field_type({:first, [key2: 1]})
      assert :ok == call_ensure_field_type({:first, [key1: :one, key2: 1]})
      assert :ok == call_ensure_field_type({:first, [key1: :one, key1: :two, key2: 1, key2: 2]})
      assert :ok == call_ensure_field_type({:first, [key1: :one, key3: :unexpected]})
      assert {:error, _} = call_ensure_field_type({:first, [key1: 1]})
      assert {:error, _} = call_ensure_field_type({:first, [1]})
      assert {:error, _} = call_ensure_field_type({:first, :not_a_list})
    end

    test "verifies value with precondition" do
      kw_precondition = Precondition.new(module: UserTypes, type_name: :kw_length_2, description: "kw_length_2_func")
      int_precondition = Precondition.new(module: UserTypes, type_name: :positive_integer, description: "positive_integer_func")
      float_precondition = Precondition.new(module: UserTypes, type_name: :positive_float, description: "positive_float_func")

      load_type_ensurer_module(
        {%{
           first: [
             {[quote(do: {:key1, {float(), unquote(float_precondition)}}), quote(do: {:key2, {integer(), unquote(int_precondition)}})],
              kw_precondition}
           ]
         }, nil}
      )

      assert :ok = call_ensure_field_type({:first, [key1: 1.2, key2: 1]})
      assert {:error, _} = call_ensure_field_type({:first, []})
      assert {:error, _} = call_ensure_field_type({:first, [key1: 1.2]})
      assert {:error, _} = call_ensure_field_type({:first, [key1: 1.0, key2: 1]})
      assert {:error, _} = call_ensure_field_type({:first, [key1: 1.2, key2: 0]})
    end
  end
end
