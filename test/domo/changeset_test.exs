defmodule Domo.ChangesetTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.Changeset

  describe "validate_type/1" do
    test "raises no schema module error if changeset has map data" do
      assert_raise RuntimeError,
                   """
                   Can't find schema module because changeset contains map data. \
                   Please, pass schema module with validate_type(changeset, schema_module) call.
                   """,
                   fn ->
                     Changeset.validate_type(%{data: %{key: :value}})
                   end
    end

    test "calls validate_required/2 with most fields required by type @t" do
      me = self()

      allow Ecto.Changeset.validate_required(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, fields, opts ->
          send(me, {:validate_required_was_called, changeset, fields, opts})
          changeset
        end

      allow CustomStructUsingDomoMetaField.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn _arg, _ -> :ok end

      changeset = %Ecto.Changeset{
        data: %CustomStructUsingDomoOptionalField{title: "hello"},
        types: %{title: :string, subtitle: :string, age: :integer, tracks: :integer}
      }

      Changeset.validate_type(changeset, trim: true)

      assert_receive {:validate_required_was_called, ^changeset, [:subtitle, :title], [trim: true]}
    end

    test "does not call validate_required/2 with Ecto.Schema typed fields of @t" do
      me = self()

      allow Ecto.Changeset.validate_required(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, fields, opts ->
          send(me, {:validate_required_was_called, changeset, fields, opts})
          changeset
        end

      allow CustomStructUsingDomoMetaField.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn _arg, _ -> :ok end

      changeset = %Ecto.Changeset{
        data: %CustomStructUsingDomoOptionalField{title: "hello"},
        types: %{title: :string, subtitle: :string, age: :integer, tracks: :integer}
      }

      Changeset.validate_type(changeset)

      assert_receive {:validate_required_was_called, ^changeset, fields, []}
      refute Enum.member?(fields, :tracks)
    end

    test "raises error if no type ensurer is for the schema module" do
      assert_raise RuntimeError, "No type ensurer for the schema module found. Please, use Domo in CustomStruct schema module.", fn ->
        Changeset.validate_type(%{data: %CustomStruct{title: "one"}})
      end
    end

    test "validates each given field of struct by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn arg, _ ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %Ecto.Changeset{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type(changeset)

      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
    end

    test "ignores __meta__ Ecto field in calling to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomoMetaField.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn arg, _ ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %Ecto.Changeset{data: %CustomStructUsingDomoMetaField{__meta__: :some, title: "hello"}}

      Changeset.validate_type(changeset)

      refute_receive {:validate_change_was_called, ^changeset, :__meta__}
      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
    end

    test "ignores Ecto.Schema typed fields in calling to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_required(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, _fields, _opts -> changeset end

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, _fun ->
          send(me, {:validate_change_was_called, field})
          changeset
        end

      allow CustomStructUsingDomoMetaField.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn _arg, _ -> :ok end

      changeset = %Ecto.Changeset{
        data: %CustomStructUsingDomoOptionalField{title: "hello"},
        types: %{title: :string, subtitle: :string, age: :integer, tracks: :integer}
      }

      Changeset.validate_type(changeset)

      refute_receive {:validate_change_was_called, :tracks}
    end

    test "validates t precondition by type ensurer and adds error in case" do
      me = self()

      allow Ecto.Changeset.validate_required(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, _fields, _opts -> changeset end

      allow Ecto.Changeset.apply_changes(any()),
        meck_options: [:passthrough],
        exec: fn changeset ->
          send(me, {:apply_changes_was_called, changeset})
          :meck.passthrough([changeset])
        end

      allow RecipientWithPrecond.TypeEnsurer.t_precondition(any()),
        meck_options: [:passthrough],
        exec: fn arg ->
          send(me, {:t_precondition_was_called, arg})
          :meck.passthrough([arg])
        end

      allow Ecto.Changeset.add_error(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, key, message ->
          send(me, {:add_error_was_called, changeset, key, message})
          :meck.passthrough([changeset, key, message])
        end

      changeset = %Ecto.Changeset{
        valid?: true,
        types: %{title: :string, name: :string, age: :integer},
        data: %RecipientWithPrecond{title: "hello", name: "name", age: 12}
      }

      Changeset.validate_type(changeset)

      assert_receive {:apply_changes_was_called, ^changeset}

      assert_receive {:t_precondition_was_called, fields}
      assert %{title: "hello", name: "name", age: 12} = fields

      refute_receive {:add_error_was_called, _, _, _}

      changeset = %Ecto.Changeset{
        valid?: true,
        types: %{title: :string, name: :string, age: :integer},
        data: %RecipientWithPrecond{title: "hello", name: "longer then 10 characters name", age: 12}
      }

      Changeset.validate_type(changeset)

      assert_receive {:apply_changes_was_called, changeset}

      assert_receive {:t_precondition_was_called, fields}
      assert %{title: "hello", name: "longer then 10 characters name", age: 12} = fields

      assert_receive {:add_error_was_called, ^changeset, :t, message}
      assert message =~ "String.length(&1.name) < 10"
    end

    test "returns empty list for ok or error list back to Ecto.Changeset.validate_change/3 call on validation" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
          changeset
        end

      changeset = %Ecto.Changeset{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type(changeset)

      assert_receive {:validate_change_got_value, []}

      changeset = %Ecto.Changeset{data: %CustomStructUsingDomo{title: :hello}}

      Changeset.validate_type(changeset)

      assert_receive {:validate_change_got_value,
                      [
                        title: """
                        Invalid value :hello for field :title of %CustomStructUsingDomo{}. \
                        Expected the value matching the <<_::_*8>> | nil type.\
                        """
                      ]}
    end

    test "returns only precond errors list back to Ecto.Changeset.validate_change/3 call given maybe_filter_precond_errors: true" do
      me = self()

      allow Ecto.Changeset.validate_required(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, _fields, _opts -> changeset end

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
          changeset
        end

      allow Ecto.Changeset.add_error(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, key, message ->
          send(me, {:add_error_was_called, key, message})
          changeset
        end

      changeset = %Ecto.Changeset{
        valid?: false,
        data: %RecipientWithPrecond{title: :mr, name: :bob, age: 500},
        types: %{title: :string, name: :string, age: :integer}
      }

      Changeset.validate_type(changeset, maybe_filter_precond_errors: true)

      assert_receive {:validate_change_got_value, [name: message]}
      assert message =~ ":bob"
      assert_receive {:validate_change_got_value, [age: message]}
      assert message =~ "&(&1 < 300)"

      changeset = %Ecto.Changeset{valid?: true, data: %RecipientWithPrecond{title: :mr, name: "Bob bob bob", age: 20}}

      Changeset.validate_type(changeset, maybe_filter_precond_errors: true)

      assert_receive {:add_error_was_called, :t, message}
      assert message =~ "&(String.length(&1.name) < 10)"
    end

    test "return error for field taken by the given function back to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
          changeset
        end

      allow Ecto.Changeset.add_error(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, _key, _message -> changeset end

      changeset = %Ecto.Changeset{
        valid?: false,
        data: %RecipientWithPrecond{title: :mr, name: :bob, age: 500},
        types: %{title: :string, name: :string, age: :integer}
      }

      Changeset.validate_type(changeset, maybe_filter_precond_errors: true, take_error_fun: &String.length(List.first(&1)))

      assert_receive {:validate_change_got_value, [name: 111]}
      assert_receive {:validate_change_got_value, [age: 154]}
    end
  end

  describe "validate_type/1 for fields given with :fields option" do
    test "raises if given fields are not in the type t()" do
      assert_raise RuntimeError, "No fields [:one, :two] are defined in the CustomStructUsingDomoOptionalField.t() type.", fn ->
        changeset = %Ecto.Changeset{data: %CustomStructUsingDomoOptionalField{title: "some_title", subtitle: "    ", age: nil}}
        Changeset.validate_type(changeset, fields: [:one, :title, :subtitle, :age, :two])
      end
    end

    test "validates given fields by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_required(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, _fields, _opts -> changeset end

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomoOptionalField.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn arg, _ ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %Ecto.Changeset{
        data: %CustomStructUsingDomoOptionalField{title: "hello", subtitle: ""},
        types: %{title: :string, subtitle: :string, age: :integer}
      }

      Changeset.validate_type(changeset, fields: [:title, :subtitle])

      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:validate_change_was_called, ^changeset, :subtitle}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
      assert_receive {:ensure_field_type_was_called, {:subtitle, ""}}
    end
  end

  describe "validate_schemaless_type/2" do
    test "raises error if no type ensurer is for the schema module" do
      assert_raise RuntimeError, "No type ensurer for the schema module found. Please, use Domo in CustomStruct schema module.", fn ->
        Changeset.validate_schemaless_type(%{data: %{title: "one"}}, CustomStruct)
      end
    end

    test "validates each field of struct by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn arg, _ ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %Ecto.Changeset{data: %{title: "hello"}}

      Changeset.validate_schemaless_type(changeset, CustomStructUsingDomo)

      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
    end

    test "returns empty list for ok or error list back to Ecto.Changeset.validate_change/3 call on validation" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
          changeset
        end

      changeset = %Ecto.Changeset{data: %{title: "hello"}}

      Changeset.validate_schemaless_type(changeset, CustomStructUsingDomo)

      assert_receive {:validate_change_got_value, []}

      changeset = %Ecto.Changeset{data: %{title: :hello}}

      Changeset.validate_schemaless_type(changeset, CustomStructUsingDomo)

      assert_receive {:validate_change_got_value,
                      [
                        title: """
                        Invalid value :hello for field :title of %CustomStructUsingDomo{}. \
                        Expected the value matching the <<_::_*8>> | nil type.\
                        """
                      ]}
    end
  end

  describe "validate_schemaless_type/2 for fields given with :fields option" do
    test "raises if given fields are not in the type t()" do
      assert_raise RuntimeError, "No fields [:one, :two] are defined in the CustomStructUsingDomoOptionalField.t() type.", fn ->
        changeset = %Ecto.Changeset{data: %{title: "some_title", subtitle: "    ", age: nil}}
        Changeset.validate_schemaless_type(changeset, CustomStructUsingDomoOptionalField, fields: [:one, :title, :subtitle, :age, :two])
      end
    end

    test "validates each given field by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any(), any()),
        meck_options: [:passthrough],
        exec: fn arg, _ ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %Ecto.Changeset{
        data: %{title: "hello"},
        types: %{title: :string, name: :string, age: :integer}
      }

      Changeset.validate_schemaless_type(changeset, CustomStructUsingDomo, fields: [:title])

      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
    end
  end

  test "import Changeset module using Domo with :changeset option" do
    allow Ecto.Changeset.validate_required(any(), any(), any()),
      meck_options: [:passthrough],
      exec: fn changeset, _fields, _opts -> changeset end

    allow Ecto.Changeset.validate_change(any(), any(), any()),
      meck_options: [:passthrough],
      exec: fn changeset, _field, _fun -> changeset end

    allow Ecto.Changeset.validate_change(any(), any(), any()),
      meck_options: [:passthrough],
      exec: fn changeset, _field, _fun -> changeset end

    allow Ecto.Changeset.apply_changes(any()),
      meck_options: [:passthrough],
      exec: fn changeset -> changeset end

    assert CustomStructImportingChangeset.validate_type_imported?()
  end
end
