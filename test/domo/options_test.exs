defmodule Domo.OptionsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  describe "use Domo with no_field option" do
    test "when set to true should prevent import of typedstruct and field macros" do
      assert_raise CompileError, ~r/undefined function typedstruct/, fn ->
        defmodule ModuleNoTypedstruct do
          use Domo, no_field: true

          typedstruct do
          end
        end
      end

      assert_raise CompileError, ~r/undefined function field/, fn ->
        defmodule ModuleNoField do
          use Domo, no_field: true

          inspect(field(:field, integer))
        end
      end
    end

    test "when set to false should import typedstruct and field macros" do
      defmodule ModuleTypedstructAndField do
        use Domo, no_field: false

        typedstruct do
          field :field, integer
        end
      end

      assert is_struct(ModuleTypedstructAndField.new!(field: 1))
    end
  end

  describe "use Domo with no_tag option" do
    test "when set to true should not import the tag/2 macro" do
      assert_raise CompileError, ~r/undefined function tag/, fn ->
        defmodule ModuleWithoutTag do
          use Domo, no_tag: true
          deftag Id, for_type: integer
          inspect(tag(123, Id))
        end
      end
    end

    test "when set to false should import the tag/2 macro" do
      defmodule ModuleWithoutTag do
        use Domo, no_tag: false
        deftag Id, for_type: integer
        inspect(tag(123, Id))
      end
    end
  end

  describe "use Domo with undefined_tag_error_as_warning option" do
    test "when set to true should emit undefined tag warning instead of an error" do
      warns =
        capture_io(:stderr, fn ->
          defmodule UndefinedTag do
            use Domo, undefined_tag_error_as_warning: true

            def somefunc do
              tag(1, Undefined)
            end
          end
        end)

      assert warns =~ ~r/tag was not defined with deftag\/2. See warning./
    end

    test "when set to false should raise an exception" do
      assert_raise CompileError, ~r/tag was not defined with deftag\/2. See warning./, fn ->
        capture_io(:stderr, fn ->
          defmodule UndefinedTagRaise do
            use Domo, undefined_tag_error_as_warning: false

            def somefunc do
              tag(2, Undefined)
            end
          end
        end)
      end
    end
  end

  describe "use Domo with unexpected_type_error_as_warning option" do
    test "when set to true should emit unexpected value type warning instead of an error" do
      warn =
        capture_io(:stderr, fn ->
          defmodule UnexpectedTypeWarn do
            use Domo, unexpected_type_error_as_warning: true

            typedstruct do
              field :field1, integer, default: 0
              field :field2, atom, default: :zero
              field :field3, float, default: 0.0
            end
          end

          [field1: :atom]
          |> UnexpectedTypeWarn.new!()
          |> UnexpectedTypeWarn.put!(:field2, "string")
          |> UnexpectedTypeWarn.merge!(field3: 1)
        end)

      assert warn =~ ~r/Unexpected value type for the field :field1/
      assert warn =~ ~r/Unexpected value type for the field :field2/
      assert warn =~ ~r/Unexpected value type for the field :field3/
    end

    test "when set to false should raise an exception" do
      defmodule UnexpectedTypeException do
        use Domo, unexpected_type_error_as_warning: false

        typedstruct do
          field :field1, integer, default: 0
          field :field2, atom, default: :zero
          field :field3, float, default: 0.0
        end
      end

      assert_raise ArgumentError, ~r//, fn -> UnexpectedTypeException.new!(field1: :atom) end

      assert_raise ArgumentError, ~r//, fn ->
        UnexpectedTypeException.put!(UnexpectedTypeException.new!([]), :field2, "string")
      end

      assert_raise ArgumentError, ~r//, fn ->
        UnexpectedTypeException.merge!(UnexpectedTypeException.new!([]), field3: 1)
      end
    end
  end

  describe "When configuration environment contains  unexpected_type_error_as_warning set to true" do
    setup do
      Application.put_env(:domo, :unexpected_type_error_as_warning, true)

      on_exit(fn ->
        Application.delete_env(:domo, :unexpected_type_error_as_warning)
      end)
    end

    test "should emit warning instead of exception" do
      warn =
        capture_io(:stderr, fn ->
          defmodule UnexpectedTypeWarn do
            use Domo

            typedstruct do
              field :field1, integer, default: 0
              field :field2, atom, default: :zero
              field :field3, float, default: 0.0
            end
          end

          [field1: :atom]
          |> UnexpectedTypeWarn.new!()
          |> UnexpectedTypeWarn.put!(:field2, "string")
          |> UnexpectedTypeWarn.merge!(field3: 1)
        end)

      assert warn =~ ~r/Unexpected value type for the field :field1/
      assert warn =~ ~r/Unexpected value type for the field :field2/
      assert warn =~ ~r/Unexpected value type for the field :field3/
    end

    test "a value passed with use Domo should override it" do
      defmodule UnexpectedTypeExceptionOverride do
        use Domo, unexpected_type_error_as_warning: false

        typedstruct do
          field :field1, integer, default: 0
          field :field2, atom, default: :zero
          field :field3, float, default: 0.0
        end
      end

      assert_raise ArgumentError, ~r//, fn ->
        UnexpectedTypeExceptionOverride.new!(field1: :atom)
      end

      assert_raise ArgumentError, ~r//, fn ->
        UnexpectedTypeExceptionOverride.put!(
          UnexpectedTypeExceptionOverride.new!([]),
          :field2,
          "string"
        )
      end

      assert_raise ArgumentError, ~r//, fn ->
        UnexpectedTypeExceptionOverride.merge!(UnexpectedTypeExceptionOverride.new!([]), field3: 1)
      end
    end
  end

  describe "When configuration environment contains undefined_tag_error_as_warning set to true" do
    setup do
      Application.put_env(:domo, :undefined_tag_error_as_warning, true)

      on_exit(fn ->
        Application.delete_env(:domo, :undefined_tag_error_as_warning)
      end)
    end

    test "should emit warning instead of exception" do
      warn =
        capture_io(:stderr, fn ->
          defmodule UndefinedTagWarning do
            use Domo

            def run do
              tag(2, UndefinedTag)
            end
          end
        end)

      assert warn =~ ~r/not defined with deftag\/2. See warning./
    end

    test "a value passed with use Domo should override it" do
      assert_raise CompileError, ~r/not defined with deftag\/2. See warning./, fn ->
        capture_io(:stderr, fn ->
          defmodule UndefinedTagWarningExec do
            use Domo, undefined_tag_error_as_warning: false

            def run do
              tag(2, UndefinedTag)
            end
          end
        end)
      end
    end
  end
end
