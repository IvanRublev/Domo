defmodule DomoFuncTest do
  use Domo.FileCase, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  setup_all do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(tmp_path())

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)

    # Evaluate modules to prepare plan file for domo mix task
    Code.eval_file("test/support/recipient.ex")
    Code.eval_file("test/support/recipient_with_precond.ex")
    Code.eval_file("test/support/empty_struct.ex")

    {:ok, []} = DomoMixTask.run([])
  end

  def build_sample_structs(_context) do
    {:ok, bob: struct!(Recipient, %{title: :mr, name: "Bob", age: 27}), joe: struct!(RecipientWithPrecond, %{title: :mr, name: "Bob", age: 37})}
  end

  describe "new/1 constructor" do
    test "makes a struct" do
      assert %Recipient{title: :mr, name: "Bob", age: 27} ==
               Recipient.new(title: :mr, name: "Bob", age: 27)

      assert %EmptyStruct{} == EmptyStruct.new()
    end

    test "raises an error for arguments mismatching struct's field types" do
      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Recipient struct:
                    * Invalid value "mr" for field :title of %Recipient{}. Expected the value matching \
                   the :mr | :ms | :dr type.
                    * Invalid value 27.5 for field :age of %Recipient{}. Expected the value matching \
                   the integer() type.\
                   """,
                   fn ->
                     _ = Recipient.new(title: "mr", name: "Bob", age: 27.5)
                   end
    end

    test "raises an error for arguments mismatching struct's field types with underlying errors" do
      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the RecipientNestedOrTypes struct:
                    * Invalid value %Recipient{age: 27, name: "Bob", title: "mr"} for field :title of %RecipientNestedOrTypes{}. \
                   Expected the value matching the :mr | %Recipient{} | :dr type.
                   Underlying errors:
                      - Expected the value matching the :mr type.
                      - Value of field :title is invalid due to Invalid value "mr" for field :title of %Recipient{}. \
                   Expected the value matching the :mr | :ms | :dr type.
                      - Expected the value matching the :dr type.\
                   """,
                   fn ->
                     _ = RecipientNestedOrTypes.new(title: %Recipient{title: "mr", name: "Bob", age: 27})
                   end
    end

    test "raises an error for arguments mismatching field's type precondition" do
      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the RecipientWithPrecond struct:
                    * Invalid value 370 for field :age of %RecipientWithPrecond{}. Expected the value matching the integer() type. \
                   And a true value from the precondition function "&(&1 < 300)" defined for RecipientWithPrecond.age() type.\
                   """,
                   fn ->
                     _ = RecipientWithPrecond.new(title: :mr, name: "Bob", age: 370)
                   end
    end

    test "raises an error for arguments mismatching struct type precondition" do
      assert_raise ArgumentError,
                   """
                   Invalid value %RecipientWithPrecond{age: 37, name: "Bob Thornton", title: :mr}. \
                   Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
                   function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
                   """,
                   fn ->
                     _ = RecipientWithPrecond.new(title: :mr, name: "Bob Thornton", age: 37)
                   end
    end

    test "issues a mismatch warning when unexpected_type_error_as_warning option is set or overriden with use Domo" do
      Application.put_env(:domo, :unexpected_type_error_as_warning, true)

      assert capture_io(:stderr, fn ->
               _ = Recipient.new(title: "mr", name: "Bob", age: 27.5)
             end) =~ "Invalid value \"mr\" for field :title of %Recipient{}."

      Application.put_env(:domo, :unexpected_type_error_as_warning, false)

      assert capture_io(:stderr, fn ->
               _ = RecipientWarnOverriden.new(title: "mr", name: "Bob", age: 27.5)
             end) =~ "Invalid value \"mr\" for field :title of %RecipientWarnOverriden{}."
    after
      Application.delete_env(:domo, :unexpected_type_error_as_warning)
    end

    test "raises an error for missing keys or keys that don't exist in the struct" do
      assert_raise ArgumentError,
                   """
                   the following keys must also be given when building \
                   struct Recipient: [:title]\
                   """,
                   fn ->
                     _ = Recipient.new(name: "Bob", age: 27)
                   end

      assert_raise KeyError, ~r/key :extra_key not found in: %Recipient/, fn ->
        _ = Recipient.new(title: :mr, name: "Bob", age: 27, extra_key: true)
      end
    end
  end

  describe "new_ok/1 constructor" do
    test "makes a struct and return it in the :ok tuple" do
      assert {:ok, %Recipient{title: :mr, name: "Bob", age: 27}} ==
               Recipient.new_ok(title: :mr, name: "Bob", age: 27)

      assert {:ok, %EmptyStruct{}} == EmptyStruct.new_ok()
    end

    test "returns :error tuple for arguments mismatching struct's field types" do
      assert {:error, error} = Recipient.new_ok(title: "mr", name: "Bob", age: 27.5)

      assert error == [
               title: """
               Invalid value "mr" for field :title of %Recipient{}. Expected the value matching \
               the :mr | :ms | :dr type.\
               """,
               age: """
               Invalid value 27.5 for field :age of %Recipient{}. Expected the value matching \
               the integer() type.\
               """
             ]
    end

    test "returns :error tuple for arguments mismatching field's type precondition" do
      assert {:error, error} = RecipientWithPrecond.new_ok(title: :mr, name: "Bob", age: 370)

      assert error == [
               age: """
               Invalid value 370 for field :age of %RecipientWithPrecond{}. Expected the value matching the integer() type. \
               And a true value from the precondition function "&(&1 < 300)" defined for RecipientWithPrecond.age() type.\
               """
             ]
    end

    test "returns :error tuple for struct type precondition" do
      assert {:error, error} = RecipientWithPrecond.new_ok(title: :mr, name: "Bob Thornton", age: 37)

      assert error == [
               t: """
               Invalid value %RecipientWithPrecond{age: 37, name: "Bob Thornton", title: :mr}. \
               Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
               function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
               """
             ]
    end

    test "returns :error tuple for a missing key" do
      assert {:error, error} = Recipient.new_ok(name: "Bob", age: 27)

      assert error == [
               title: """
               Invalid value nil for field :title of %Recipient{}. Expected the value matching \
               the :mr | :ms | :dr type.\
               """
             ]
    end

    test "makes a new struct discarding keys that don't exist in the struct" do
      assert {:ok, %Recipient{title: :mr, name: "Bob", age: 27}} ==
               Recipient.new_ok(title: :mr, name: "Bob", age: 27, extra_key: true)

      assert {:ok, %EmptyStruct{}} == EmptyStruct.new_ok(extra_key: true)
    end
  end

  describe "ensure_type!/1" do
    setup [:build_sample_structs]

    test "checks if the struct matches it's type", %{bob: bob} do
      dr_bob = %{bob | title: :dr}

      assert dr_bob == Recipient.ensure_type!(dr_bob)
    end

    test "raises an error for the struct mismatching it's type", %{bob: bob} do
      malformed_bob = %{bob | name: :bob_hope}

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the Recipient struct:
                    * Invalid value :bob_hope for field :name of %Recipient{}. Expected the value \
                   matching the <<_::_*8>> type.\
                   """,
                   fn ->
                     _ = Recipient.ensure_type!(malformed_bob)
                   end
    end

    test "raises an error for arguments mismatching field's type precondition", %{joe: joe} do
      malformed_joe = %{joe | age: 450}

      assert_raise ArgumentError,
                   """
                   the following values should have types defined for fields of the RecipientWithPrecond struct:
                    * Invalid value 450 for field :age of %RecipientWithPrecond{}. Expected the value matching the integer() type. \
                   And a true value from the precondition function "&(&1 < 300)" defined for RecipientWithPrecond.age() type.\
                   """,
                   fn ->
                     _ = RecipientWithPrecond.ensure_type!(malformed_joe)
                   end
    end

    test "raises an error for arguments mismatching struct type precondition", %{joe: joe} do
      malformed_joe = %{joe | name: "Bob Thornton"}

      assert_raise ArgumentError,
                   """
                   Invalid value %RecipientWithPrecond{age: 37, name: "Bob Thornton", title: :mr}. \
                   Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
                   function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
                   """,
                   fn ->
                     _ = RecipientWithPrecond.ensure_type!(malformed_joe)
                   end
    end

    test "issues a mismatch warning when unexpected_type_error_as_warning option is set or overriden with use Domo",
         %{bob: bob} do
      malformed_bob = %{bob | name: :bob_hope}
      Application.put_env(:domo, :unexpected_type_error_as_warning, true)

      assert capture_io(:stderr, fn ->
               _ = Recipient.ensure_type!(malformed_bob)
             end) =~ "Invalid value :bob_hope for field :name of %Recipient{}."

      Application.put_env(:domo, :unexpected_type_error_as_warning, false)

      assert capture_io(:stderr, fn ->
               malformed_bob = struct!(RecipientWarnOverriden, Map.from_struct(malformed_bob))
               _ = RecipientWarnOverriden.ensure_type!(malformed_bob)
             end) =~ "Invalid value :bob_hope for field :name of %RecipientWarnOverriden{}."
    after
      Application.delete_env(:domo, :unexpected_type_error_as_warning)
    end

    test "raises an error if the passed struct's name differs from the module's name" do
      assert_raise ArgumentError,
                   """
                   the Recipient structure should be passed as \
                   the first argument value instead of EmptyStruct.\
                   """,
                   fn ->
                     Recipient.ensure_type!(%EmptyStruct{})
                   end
    end
  end

  describe "ensure_type_ok/1" do
    setup [:build_sample_structs]

    test "returns :ok if the strcut matches it's type", %{bob: bob} do
      dr_bob = %{bob | title: :dr}

      assert {:ok, dr_bob} == Recipient.ensure_type_ok(dr_bob)
    end

    test "returns an :error tuple for the struct mismatching it's type", %{bob: bob} do
      malformed_bob = %{bob | name: :bob_hope}

      assert {:error,
              name: """
              Invalid value :bob_hope for field :name of %Recipient{}. Expected the value \
              matching the <<_::_*8>> type.\
              """} = Recipient.ensure_type_ok(malformed_bob)
    end

    test "returns :error tuple for arguments mismatching field's type precondition", %{joe: joe} do
      malformed_joe = %{joe | age: 450}

      assert {:error,
              age: """
              Invalid value 450 for field :age of %RecipientWithPrecond{}. Expected the value matching the integer() type. \
              And a true value from the precondition function "&(&1 < 300)" defined for RecipientWithPrecond.age() type.\
              """} = RecipientWithPrecond.ensure_type_ok(malformed_joe)
    end

    test "returns :error tuple for struct type precondition", %{joe: joe} do
      malformed_joe = %{joe | name: "Bob Thornton"}

      assert {:error,
              t: """
              Invalid value %RecipientWithPrecond{age: 37, name: "Bob Thornton", title: :mr}. \
              Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
              function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
              """} = RecipientWithPrecond.ensure_type_ok(malformed_joe)
    end

    test "raises an error if the passed struct's name differs from the module's name" do
      assert_raise ArgumentError,
                   """
                   the Recipient structure should be passed as \
                   the first argument value instead of EmptyStruct.\
                   """,
                   fn ->
                     Recipient.ensure_type_ok(%EmptyStruct{})
                   end
    end
  end
end
