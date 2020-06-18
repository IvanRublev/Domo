defmodule Domo.CompilationChecksTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "use Domo called outside of the module scope should raise CompileError" do
    assert_raise CompileError,
                 "nofile: use Domo should be called in a module scope only. Try import Domo instead.",
                 fn ->
                   Code.compile_quoted(quote(do: use(Domo)))
                 end

    assert_raise CompileError,
                 "nofile: use Domo should be called in a module scope only. Try import Domo instead.",
                 fn ->
                   Code.compile_quoted(
                     quote do
                       defmodule M do
                         def fff do
                           use Domo
                         end
                       end
                     end
                   )
                 end
  end

  describe "After compilation a module using Domo should" do
    test "emit missing alias warnings for non tag modules in tag/untag! calls" do
      warns =
        capture_io(:stderr, fn ->
          defmodule Chk10 do
            use Domo, undefined_tag_error_as_warning: true

            def somefunc do
              tag(77, Only)
              untag!({Utt, 2}, Utt)
            end
          end
        end)

      for m <- ["Only", "Utt"] do
        assert warns =~
                 "#{m} is not a tag defined with deftag/2. Have you missed an alias Some.Path.#{m}?"
      end

      assert warns =~ ~r/[^:]+:\d+: .*somefunc\/0/
    end

    test "raise CompileError when any tags were not defined with deftag/2" do
      assert_raise CompileError,
                   ~r/A tag was not defined with deftag\/2. See warning./,
                   fn ->
                     capture_io(:stderr, fn ->
                       defmodule Chk15 do
                         use Domo

                         def somefunc do
                           tag(1, Undefined)
                         end
                       end
                     end)
                   end
    end

    test "Not emit missing alias warning for module used with tag/untag! operator defined as tag" do
      warns =
        capture_io(:stderr, fn ->
          defmodule Chk20 do
            use Domo, undefined_tag_error_as_warning: true
            deftag SomeTag, for_type: integer
          end

          defmodule Chk21 do
            use Domo, undefined_tag_error_as_warning: true

            alias Chk20.SomeTag

            deftag AnotherTag, for_type: integer
            deftag ThirdTag, for_type: integer

            def somefunc do
              tag(3, SomeTag)
              untag!({AnotherTag, 2}, AnotherTag)
            end
          end
        end)

      assert warns == ""
    end
  end
end
