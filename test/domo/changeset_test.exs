defmodule Domo.ChangesetTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.Changeset
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  setup_all do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(tmp_path())

    on_exit(fn ->
      File.rm_rf(tmp_path())
      Code.compiler_options(ignore_module_conflict: false)
    end)

    # Evaluate modules to prepare plan file for domo mix task
    Code.eval_file("test/support/custom_struct_using_domo.ex")

    DomoMixTask.run([])

    :ok
  end

  describe "validate_type/1" do
    test "raises no schema module error if changesed has map data" do
      assert_raise RuntimeError,
                   """
                   Can't find schema module because changeset contains map data. \
                   Please, pass schema module with validate_type(changeset, schema_module) call.
                   """,
                   fn ->
                     Changeset.validate_type(%{data: %{key: :value}})
                   end
    end

    test "raises error if no type ensurer is for the schema module" do
      assert_raise RuntimeError, "No type ensurer for the schema module found. Please, use Domo in CustomStruct schema module.", fn ->
        Changeset.validate_type(%{data: %CustomStruct{title: "one"}})
      end
    end

    test "validates each given field of struct by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any()),
        meck_options: [:passthrough],
        exec: fn arg ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type(changeset)

      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
    end

    test "ignores hidden Ecto fields starting with underscore like __meta__ in calling to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomo.TypeEnsurer.fields(), meck_options: [:passthrough], return: [:__meta__, :__hidden__, :field]

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any()),
        meck_options: [:passthrough],
        exec: fn arg ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type(changeset)

      refute_receive {:validate_change_was_called, ^changeset, :__meta__}
      refute_receive {:validate_change_was_called, ^changeset, :__hidden__}
      assert_receive {:validate_change_was_called, ^changeset, :field}
      assert_receive {:ensure_field_type_was_called, {:field, nil}}
    end

    test "returns empty list for ok or error list back to Ecto.Changeset.validate_change/3 call on validation" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
        end

      changeset = %{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type(changeset)

      assert_receive {:validate_change_got_value, []}

      changeset = %{data: %CustomStructUsingDomo{title: :hello}}

      Changeset.validate_type(changeset)

      assert_receive {:validate_change_got_value,
                      [
                        title: """
                        Invalid value :hello for field :title of %CustomStructUsingDomo{}. \
                        Expected the value matching the <<_::_*8>> | nil type.\
                        """
                      ]}
    end
  end

  describe "validate_type_fields/2" do
    test "raises no schema module error if changesed has map data" do
      assert_raise RuntimeError,
                   """
                   Can't find schema module because changeset contains map data. \
                   Please, pass schema module with validate_type(changeset, schema_module) call.
                   """,
                   fn ->
                     Changeset.validate_type_fields(%{data: %{key: :value}}, [:key])
                   end
    end

    test "raises error if no type ensurer is for the schema module" do
      assert_raise RuntimeError, "No type ensurer for the schema module found. Please, use Domo in CustomStruct schema module.", fn ->
        Changeset.validate_type_fields(%{data: %CustomStruct{title: "one"}}, [:title])
      end
    end

    test "returns changeset as is if no fields are given" do
      changeset = %{data: %{title: "hello"}}

      assert Changeset.validate_type_fields(changeset, []) === changeset
    end

    test "validates each field of struct by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any()),
        meck_options: [:passthrough],
        exec: fn arg ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type_fields(changeset, [:one, :two])

      assert_receive {:validate_change_was_called, ^changeset, :one}
      assert_receive {:validate_change_was_called, ^changeset, :two}
      assert_receive {:ensure_field_type_was_called, {:one, nil}}
      assert_receive {:ensure_field_type_was_called, {:two, nil}}
    end

    test "returns empty list for ok or error list back to Ecto.Changeset.validate_change/3 call on validation" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
        end

      changeset = %{data: %CustomStructUsingDomo{title: "hello"}}

      Changeset.validate_type_fields(changeset, [:title])

      assert_receive {:validate_change_got_value, []}

      changeset = %{data: %CustomStructUsingDomo{title: :hello}}

      Changeset.validate_type_fields(changeset, [:title])

      assert_receive {:validate_change_got_value,
                      [
                        title: """
                        Invalid value :hello for field :title of %CustomStructUsingDomo{}. \
                        Expected the value matching the <<_::_*8>> | nil type.\
                        """
                      ]}
    end
  end

  describe "validate_type/2" do
    test "raises error if no type ensurer is for the schema module" do
      assert_raise RuntimeError, "No type ensurer for the schema module found. Please, use Domo in CustomStruct schema module.", fn ->
        Changeset.validate_type(%{data: %{title: "one"}}, CustomStruct)
      end
    end

    test "validates each field of struct by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any()),
        meck_options: [:passthrough],
        exec: fn arg ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %{data: %{title: "hello"}}

      Changeset.validate_type(changeset, CustomStructUsingDomo)

      assert_receive {:validate_change_was_called, ^changeset, :title}
      assert_receive {:ensure_field_type_was_called, {:title, "hello"}}
    end

    test "returns empty list for ok or error list back to Ecto.Changeset.validate_change/3 call on validation" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
        end

      changeset = %{data: %{title: "hello"}}

      Changeset.validate_type(changeset, CustomStructUsingDomo)

      assert_receive {:validate_change_got_value, []}

      changeset = %{data: %{title: :hello}}

      Changeset.validate_type(changeset, CustomStructUsingDomo)

      assert_receive {:validate_change_got_value,
                      [
                        title: """
                        Invalid value :hello for field :title of %CustomStructUsingDomo{}. \
                        Expected the value matching the <<_::_*8>> | nil type.\
                        """
                      ]}
    end
  end

  describe "validate_type_fields/3" do
    test "raises error if no type ensurer is for the schema module" do
      assert_raise RuntimeError, "No type ensurer for the schema module found. Please, use Domo in CustomStruct schema module.", fn ->
        Changeset.validate_type_fields(%{data: %{title: "one"}}, CustomStruct, [:title])
      end
    end

    test "returns changeset as is if no fields are given" do
      changeset = %{data: %{title: "hello"}}

      assert Changeset.validate_type_fields(changeset, CustomStruct, []) === changeset
    end

    test "validates each given field of struct by type ensurer in call to Ecto.Changeset.validate_change/3" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          send(me, {:validate_change_was_called, changeset, field})
          fun.(field, Map.get(changeset.data, field))
          changeset
        end

      allow CustomStructUsingDomo.TypeEnsurer.ensure_field_type(any()),
        meck_options: [:passthrough],
        exec: fn arg ->
          send(me, {:ensure_field_type_was_called, arg})
          :ok
        end

      changeset = %{data: %{title: "hello"}}

      Changeset.validate_type_fields(changeset, CustomStructUsingDomo, [:one_field, :other_field])

      assert_receive {:validate_change_was_called, ^changeset, :one_field}
      assert_receive {:validate_change_was_called, ^changeset, :other_field}
      assert_receive {:ensure_field_type_was_called, {:one_field, nil}}
      assert_receive {:ensure_field_type_was_called, {:other_field, nil}}
    end

    test "returns empty list for ok or error list back to Ecto.Changeset.validate_change/3 call on validation" do
      me = self()

      allow Ecto.Changeset.validate_change(any(), any(), any()),
        exec: fn changeset, field, fun ->
          reply = fun.(field, Map.get(changeset.data, field))
          send(me, {:validate_change_got_value, reply})
        end

      changeset = %{data: %{title: "hello"}}

      Changeset.validate_type_fields(changeset, CustomStructUsingDomo, [:title])

      assert_receive {:validate_change_got_value, []}

      changeset = %{data: %{title: :hello}}

      Changeset.validate_type_fields(changeset, CustomStructUsingDomo, [:title])

      assert_receive {:validate_change_got_value,
                      [
                        title: """
                        Invalid value :hello for field :title of %CustomStructUsingDomo{}. \
                        Expected the value matching the <<_::_*8>> | nil type.\
                        """
                      ]}
    end
  end
end
