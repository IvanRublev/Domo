defmodule Domo.TypeEnsurerFactory.GeneratorTypeEnsurerModuleStructFieldTest do
  use Domo.FileCase, async: false
  use Placebo

  import GeneratorTestHelper

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

    test "should have only universal match_spec function for the struct" do
      ensurer_quoted =
        %{
          first: [
            quote(do: %CustomStructUsingDomo{title: <<_::_*8>>}),
            quote(do: %CustomStructUsingDomo{title: nil}),
            quote(do: nil)
          ]
        }
        |> ResolverTestHelper.add_empty_precond_to_spec()
        |> type_ensurer_quoted_with_no_preconds()

      ensurer_string = Macro.to_string(ensurer_quoted)

      assert ensurer_string =~ ~r/do_match_spec\({:"%CustomStructUsingDomo{}"\,/
    end

    test "should have only universal match_spec function for the struct in nested container" do
      ensurer_quoted =
        %{
          first: [
            quote(do: [{%CustomStructUsingDomo{title: <<_::_*8>>}}]),
            quote(do: [{%CustomStructUsingDomo{title: nil}}]),
            quote(do: nil)
          ]
        }
        |> ResolverTestHelper.add_empty_precond_to_spec()
        |> type_ensurer_quoted_with_no_preconds()

      ensurer_string = Macro.to_string(ensurer_quoted)

      assert ensurer_string =~ ~r/do_match_spec\({:"%CustomStructUsingDomo{}"\,/
    end
  end
end
