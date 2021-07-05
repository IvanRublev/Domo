defmodule Domo.TypeEnsurerFactory.GeneratorTypeEnsurerModuleStructFieldTest do
  use Domo.FileCase, async: false
  use Placebo

  import GeneratorTestHelper

  alias Domo.TypeEnsurerFactory.Precondition

  setup do
    on_exit(fn ->
      :code.purge(TypeEnsurer)
      :code.delete(TypeEnsurer)
    end)

    :ok
  end

  def call_ensure_type({_field, _value} = subject) do
    apply(TypeEnsurer, :ensure_field_type, [subject])
  end

  describe "TypeEnsurer module for field of struct type that does not use Domo" do
    test "ensures field's value" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %CustomStruct{})]
      })

      assert :ok == call_ensure_type({:first, %CustomStruct{title: :one}})
      assert :ok == call_ensure_type({:first, %CustomStruct{title: nil}})
      assert :ok == call_ensure_type({:first, %CustomStruct{title: "one"}})
      assert {:error, _} = call_ensure_type({:first, %{}})
      assert {:error, _} = call_ensure_type({:first, :not_a_struct})
    end

    test "ensures field's value accounting given struct's keys and value types" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [quote(do: %CustomStruct{title: <<_::_*8>>}), quote(do: %CustomStruct{title: nil})]
      })

      assert :ok == call_ensure_type({:first, %CustomStruct{title: "one"}})
      assert :ok == call_ensure_type({:first, %CustomStruct{title: nil}})
      assert {:error, _} = call_ensure_type({:first, %CustomStruct{title: :one}})
      assert {:error, _} = call_ensure_type({:first, %{}})
      assert {:error, _} = call_ensure_type({:first, :not_a_struct})
    end

    test "ensures given keys and value types with preconditions" do
      struct_precondition = Precondition.new(module: UserTypes, type_name: :capital_title, description: "capital_title_func")
      precondition = Precondition.new(module: UserTypes, type_name: :binary_6, description: "binary_6_func")

      load_type_ensurer_module(
        {%{
           first: [
             {
               quote(context: String, do: %CustomStruct{title: {<<_::_*8>>, unquote(precondition)}}),
               struct_precondition
             }
           ]
         }, nil}
      )

      assert :ok == call_ensure_type({:first, %CustomStruct{title: "Hello!"}})
      assert {:error, _} = call_ensure_type({:first, %CustomStruct{title: "Hello"}})
      assert {:error, _} = call_ensure_type({:first, %CustomStruct{title: "hello!"}})
    end
  end

  describe "TypeEnsurer module for field of struct that use Domo" do
    test "ensures field's value by delegating to the struct's TypeEnsurer" do
      load_type_ensurer_module_with_no_preconds(%{
        first: [
          quote(do: %CustomStructUsingDomo{}),
          quote(do: %CustomStructUsingDomo{title: nil})
        ]
      })

      allow CustomStructUsingDomo.ensure_type_ok(any()), exec: fn struct -> {:ok, struct} end

      instance = %CustomStructUsingDomo{title: :one}
      call_ensure_type({:first, instance})

      assert_called CustomStructUsingDomo.ensure_type_ok(instance)
    end

    test "ensures field's value by delegating to type ensurer and using precondition" do
      struct_precondition = Precondition.new(module: UserTypes, type_name: :capital_title, description: "capital_title_func")

      load_type_ensurer_module(
        {%{
           first: [
             {
               quote(context: String, do: %CustomStructWithEnsureOk{title: {<<_::_*8>>, nil}}),
               struct_precondition
             }
           ]
         }, nil}
      )

      assert :ok == call_ensure_type({:first, %CustomStructWithEnsureOk{title: "Hello"}})
      assert {:error, _} = call_ensure_type({:first, %CustomStructWithEnsureOk{title: "hello"}})
    end
  end
end
