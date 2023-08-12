defmodule DomoFuncTest do
  use Domo.FileCase, async: false
  use Placebo

  import ExUnit.CaptureIO

  alias Domo.CodeEvaluation
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias Domo.MixProject

  setup_all do
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true

    :ok
  end

  def build_sample_structs(_context) do
    {:ok, bob: struct!(Recipient, %{title: :mr, name: "Bob", age: 27}), joe: struct!(RecipientWithPrecond, %{title: :mr, name: "Bob", age: 37})}
  end

  describe "new!/1 constructor" do
    test "makes a struct" do
      assert %Recipient{title: :mr, name: "Bob", age: 27} ==
               Recipient.new!(title: :mr, name: "Bob", age: 27)

      assert %EmptyStruct{} == EmptyStruct.new!()
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
                     _ = Recipient.new!(title: "mr", name: "Bob", age: 27.5)
                   end
    end

    test "raises an error for arguments mismatching struct's field types with underlying errors" do
      message_regex =
        """
        the following values should have types defined for fields of the RecipientNestedOrTypes struct:
         * Invalid value %Recipient{__fields_pattern__} for field :title of %RecipientNestedOrTypes{}. \
        Expected the value matching the :mr | %Recipient{} | :dr type.
        Underlying errors:
           - Value of field :title is invalid due to Invalid value "mr" for field :title of %Recipient{}. \
        Expected the value matching the :mr | :ms | :dr type.\
        """
        |> Regex.escape()
        |> String.replace("__fields_pattern__", ".*age: 27.*")
        |> Regex.compile!()

      assert_raise ArgumentError,
                   message_regex,
                   fn ->
                     _ = RecipientNestedOrTypes.new!(title: %Recipient{title: "mr", name: "Bob", age: 27})
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
                     _ = RecipientWithPrecond.new!(title: :mr, name: "Bob", age: 370)
                   end
    end

    test "raises an error for arguments mismatching struct type precondition" do
      message_regex =
        """
        Invalid value %RecipientWithPrecond{__fields_pattern__}. \
        Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
        function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
        """
        |> Regex.escape()
        |> String.replace("__fields_pattern__", ".*age: 37.*")
        |> Regex.compile!()

      assert_raise ArgumentError,
                   message_regex,
                   fn ->
                     _ = RecipientWithPrecond.new!(title: :mr, name: "Bob Thornton", age: 37)
                   end
    end

    test "issues a mismatch warning when `unexpected_type_error_as_warning` option is set or overridden with use Domo" do
      Application.put_env(:domo, :unexpected_type_error_as_warning, true)

      assert capture_io(:stderr, fn ->
               _ = Recipient.new!(title: "mr", name: "Bob", age: 27.5)
             end) =~ "Invalid value \"mr\" for field :title of %Recipient{}."

      Application.put_env(:domo, :unexpected_type_error_as_warning, false)

      assert capture_io(:stderr, fn ->
               _ = RecipientWarnOverriden.new!(title: "mr", name: "Bob", age: 27.5)
             end) =~ "Invalid value \"mr\" for field :title of %RecipientWarnOverriden{}."
    after
      Application.delete_env(:domo, :unexpected_type_error_as_warning)
    end

    test "ensures remote types as any type listing them in `remote_types_as_any` option or overridden with use Domo" do
      DomoMixTask.start_plan_collection()

      compile_recipient_foreign_struct(
        "RecipientForeignStructsAsAnyInUsing",
        "remote_types_as_any: [{EmptyStruct, :t}, {CustomStructUsingDomo, [:t]}]",
        "alias The.Nested.EmptyStruct"
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert _ =
               apply(RecipientForeignStructsAsAnyInUsing, :new!, [[placeholder: :not_empty_struct, custom_struct: :not_custom_struct, title: "hello"]])

      Application.put_env(:domo, :remote_types_as_any, [{The.Nested.EmptyStruct, :t}, CustomStructUsingDomo: [:t]])

      DomoMixTask.start_plan_collection()
      compile_recipient_foreign_struct("RecipientForeignStructs")
      DomoMixTask.process_plan({:ok, []}, [])

      assert _ = apply(RecipientForeignStructs, :new!, [[placeholder: :not_empty_struct, custom_struct: :not_custom_struct, title: "hello"]])

      assert_raise ArgumentError, ~r/Invalid value :hello for field :title of %RecipientForeignStructs{}./, fn ->
        apply(RecipientForeignStructs, :new!, [[placeholder: :not_empty_struct, custom_struct: :not_custom_struct, title: :hello]])
      end

      Application.put_env(:domo, :remote_types_as_any, CustomStructUsingDomo: :t)

      DomoMixTask.start_plan_collection()

      compile_recipient_foreign_struct(
        "RecipientForeignStructsRemoteTypesAsAnyOverriden",
        "remote_types_as_any: [Recipient: [:name]]"
      )

      DomoMixTask.process_plan({:ok, []}, [])

      assert _ =
               apply(RecipientForeignStructsRemoteTypesAsAnyOverriden, :new!, [
                 [placeholder: The.Nested.EmptyStruct.new!(), custom_struct: :not_custom_struct, title: :not_a_string]
               ])

      assert_raise ArgumentError,
                   ~r/Invalid value :not_empty_struct for field :placeholder of %RecipientForeignStructsRemoteTypesAsAnyOverriden{}./,
                   fn ->
                     apply(RecipientForeignStructsRemoteTypesAsAnyOverriden, :new!, [
                       [
                         placeholder: :not_empty_struct,
                         custom_struct: :not_custom_struct,
                         title: :not_a_string
                       ]
                     ])
                   end
    after
      Application.delete_env(:domo, :remote_types_as_any)
    end

    test "raises error for wrong formatted `remote_types_as_any` option" do
      Application.put_env(:domo, :remote_types_as_any, [The.Nested.EmptyStruct, CustomStructUsingDomo: [:t]])

      return_value = compile_recipient_foreign_struct("RecipientForeignStructs")
      assert {:error, [%{message: message}]} = return_value
      assert message =~ ":remote_types_as_any option value must be of the following shape"

      Application.delete_env(:domo, :remote_types_as_any)

      return_value =
        compile_recipient_foreign_struct(
          "RecipientForeignStructsRemoteTypesAsAnyOverriden",
          "remote_types_as_any: [{Recipient, :name}, CustomStructUsingDomo: [1]]"
        )

      assert {:error, [%{message: message}]} = return_value
      assert message =~ ":remote_types_as_any option value must be of the following shape"
    after
      Application.delete_env(:domo, :remote_types_as_any)
    end

    test "raises an error for missing keys or keys that don't exist in the struct" do
      assert_raise ArgumentError,
                   """
                   the following keys must also be given when building \
                   struct Recipient: [:title]\
                   """,
                   fn ->
                     _ = Recipient.new!(name: "Bob", age: 27)
                   end

      assert_raise KeyError, ~r/key :extra_key not found/, fn ->
        _ = Recipient.new!(title: :mr, name: "Bob", age: 27, extra_key: true)
      end
    end
  end

  describe "new/1 constructor" do
    test "makes a struct and return it in the :ok tuple" do
      assert {:ok, %Recipient{title: :mr, name: "Bob", age: 27}} ==
               Recipient.new(title: :mr, name: "Bob", age: 27)

      assert {:ok, %EmptyStruct{}} == EmptyStruct.new()
    end

    test "returns :error tuple for arguments mismatching struct's field types" do
      assert {:error, error} = Recipient.new(title: "mr", name: "Bob", age: 27.5)

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
      assert {:error, error} = RecipientWithPrecond.new(title: :mr, name: "Bob", age: 370)

      assert error == [
               age: """
               Invalid value 370 for field :age of %RecipientWithPrecond{}. Expected the value matching the integer() type. \
               And a true value from the precondition function "&(&1 < 300)" defined for RecipientWithPrecond.age() type.\
               """
             ]
    end

    test "returns :error tuple for struct type precondition" do
      assert {:error, error} = RecipientWithPrecond.new(title: :mr, name: "Bob Thornton", age: 37)

      assert [t: message] = error

      message_regex =
        """
        Invalid value %RecipientWithPrecond{__fields_pattern__}. \
        Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
        function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
        """
        |> Regex.escape()
        |> String.replace("__fields_pattern__", ".*age: 37.*")
        |> Regex.compile!()

      assert message =~ message_regex
    end

    test "returns :error tuple for a missing key" do
      assert {:error, error} = Recipient.new(name: "Bob", age: 27)

      assert error == [
               title: """
               Invalid value nil for field :title of %Recipient{}. Expected the value matching \
               the :mr | :ms | :dr type.\
               """
             ]
    end

    test "makes a new struct discarding keys that don't exist in the struct" do
      assert {:ok, %Recipient{title: :mr, name: "Bob", age: 27}} ==
               Recipient.new(title: :mr, name: "Bob", age: 27, extra_key: true)

      assert {:ok, %EmptyStruct{}} == EmptyStruct.new(extra_key: true)
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

      message_regex =
        """
        Invalid value %RecipientWithPrecond{__fields_pattern__}. \
        Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
        function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
        """
        |> Regex.escape()
        |> String.replace("__fields_pattern__", ".*age: 37.*")
        |> Regex.compile!()

      assert_raise ArgumentError,
                   message_regex,
                   fn ->
                     _ = RecipientWithPrecond.ensure_type!(malformed_joe)
                   end
    end

    test "issues a mismatch warning when `unexpected_type_error_as_warning` option is set or overridden with use Domo",
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

  describe "ensure_type/1" do
    setup [:build_sample_structs]

    test "returns :ok if the struct matches it's type", %{bob: bob} do
      dr_bob = %{bob | title: :dr}

      assert {:ok, dr_bob} == Recipient.ensure_type(dr_bob)
    end

    test "returns an :error tuple for the struct mismatching it's type", %{bob: bob} do
      malformed_bob = %{bob | name: :bob_hope}

      assert {:error,
              name: """
              Invalid value :bob_hope for field :name of %Recipient{}. Expected the value \
              matching the <<_::_*8>> type.\
              """} = Recipient.ensure_type(malformed_bob)
    end

    test "returns :error tuple for arguments mismatching field's type precondition", %{joe: joe} do
      malformed_joe = %{joe | age: 450}

      assert {:error,
              age: """
              Invalid value 450 for field :age of %RecipientWithPrecond{}. Expected the value matching the integer() type. \
              And a true value from the precondition function "&(&1 < 300)" defined for RecipientWithPrecond.age() type.\
              """} = RecipientWithPrecond.ensure_type(malformed_joe)
    end

    test "returns :error tuple for struct type precondition", %{joe: joe} do
      malformed_joe = %{joe | name: "Bob Thornton"}

      assert {:error, t: message} = RecipientWithPrecond.ensure_type(malformed_joe)

      message_regex =
        """
        Invalid value %RecipientWithPrecond{__fields_pattern__}. \
        Expected the value matching the RecipientWithPrecond.t() type. And a true value from the precondition \
        function "&(String.length(&1.name) < 10)" defined for RecipientWithPrecond.t() type.\
        """
        |> Regex.escape()
        |> String.replace("__fields_pattern__", ".*age: 37.*")
        |> Regex.compile!()

      assert message =~ message_regex
    end

    test "raises an error if the passed struct's name differs from the module's name" do
      assert_raise ArgumentError,
                   """
                   the Recipient structure should be passed as \
                   the first argument value instead of EmptyStruct.\
                   """,
                   fn ->
                     Recipient.ensure_type(%EmptyStruct{})
                   end
    end
  end

  test "typed_fields/1 returns struct fields having specific (not any) type sorted alphabetically with/without meta fields" do
    DomoMixTask.start_plan_collection()
    compile_meta_fields_struct("MetaDefaults")
    DomoMixTask.process_plan({:ok, []}, [])

    assert apply(MetaDefaults, :typed_fields, []) == [:custom_struct, :title]
    assert apply(MetaDefaults, :typed_fields, [[include_any_typed: true]]) == [:custom_struct, :placeholder, :title]

    assert apply(MetaDefaults, :typed_fields, [[include_meta: true]]) == [:__hidden_atom__, :__meta__, :custom_struct, :title]

    assert apply(MetaDefaults, :typed_fields, [[include_meta: true, include_any_typed: true]]) == [
             :__hidden_any__,
             :__hidden_atom__,
             :__meta__,
             :custom_struct,
             :placeholder,
             :title
           ]
  end

  test "required_fields/1 returns struct fields having not nil and not any type sorted alphabetically with/without meta fields" do
    DomoMixTask.start_plan_collection()
    compile_meta_fields_struct("MetaDefaults")
    DomoMixTask.process_plan({:ok, []}, [])

    assert apply(MetaDefaults, :required_fields, []) == [:custom_struct, :title]
    assert apply(MetaDefaults, :required_fields, [[include_meta: true]]) == [:__hidden_atom__, :__meta__, :custom_struct, :title]
  end

  test "__t__/0 returns string of type definition for the struct" do
    DomoMixTask.start_plan_collection()
    compile_meta_fields_struct("MetaDefaults")
    DomoMixTask.process_plan({:ok, []}, [])

    descr = apply(MetaDefaults, :__t__, [])

    case ElixirVersion.version() do
      [1, minor, _] when minor < 12 ->
        assert descr ==
                 "%MetaDefaults{__hidden_any__: any(), __hidden_atom__: atom(), __meta__: String.t(), custom_struct: CustomStructUsingDomo.t(), placeholder: term(), title: Recipient.name()}"

      [1, minor, _] when minor >= 12 ->
        assert descr == """
               %MetaDefaults{
                 __hidden_any__: any(),
                 __hidden_atom__: atom(),
                 __meta__: String.t(),
                 custom_struct: CustomStructUsingDomo.t(),
                 placeholder: term(),
                 title: Recipient.name()
               }\
               """
    end
  end

  defp compile_recipient_foreign_struct(module_name, use_arg \\ nil, pre_use \\ "") do
    path = MixProject.out_of_project_tmp_path("/recipient_foreign_#{Enum.random(100..100_000)}.ex")

    use_domo =
      ["use Domo", use_arg, "skip_defaults: true"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    File.write!(path, """
    defmodule #{module_name} do
      #{pre_use}
      #{use_domo}

      @enforce_keys [:placeholder, :custom_struct, :title]
      defstruct @enforce_keys

      @type t :: %__MODULE__{
              placeholder: The.Nested.EmptyStruct.t(),
              custom_struct: CustomStructUsingDomo.t(),
              title: Recipient.name()
            }
    end
    """)

    CompilerHelpers.compile_with_elixir()
  end

  defp compile_meta_fields_struct(module_name) do
    path = MixProject.out_of_project_tmp_path("/meta_fields_#{Enum.random(100..100_000)}.ex")

    File.write!(path, """
    defmodule #{module_name} do
      use Domo, skip_defaults: true

      @enforce_keys [:placeholder, :__hidden_any__, :__hidden_atom__, :__meta__, :custom_struct, :title]
      defstruct @enforce_keys

      @type t :: %__MODULE__{
              placeholder: term(),
              __hidden_any__: any(),
              __hidden_atom__: atom(),
              __meta__: String.t(),
              custom_struct: CustomStructUsingDomo.t(),
              title: Recipient.name()
            }
    end
    """)

    CompilerHelpers.compile_with_elixir()
  end
end
