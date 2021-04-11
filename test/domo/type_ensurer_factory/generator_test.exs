defmodule Domo.TypeEnsurerFactory.GeneratorTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.MixProjectHelper
  alias Mix.Tasks.Compile.Domo, as: DomoMixTask

  @moduletag types_content: %{}

  setup tags do
    project = MixProjectHelper.global_stub()
    types_file = DomoMixTask.manifest_path(project, :types)
    code_path = DomoMixTask.generated_code_path(project)

    types_content = tags.types_content

    unless is_nil(types_content) do
      File.write!(types_file, :erlang.term_to_binary(types_content))
    end

    on_exit(fn ->
      _ = File.rm(types_file)
    end)

    %{types_file: types_file, code_path: code_path}
  end

  describe "generate/2" do
    test "makes code directory", %{types_file: types_file, code_path: code_path} do
      File.rm_rf(code_path)

      Generator.generate(types_file, code_path)
      assert true == File.exists?(code_path)
    end

    test "returns error if make of the directory failed", %{
      types_file: types_file,
      code_path: code_path
    } do
      defmodule FailingMkdirFile do
        def mkdir_p(_path), do: {:error, :enomem}
      end

      assert %Error{
               compiler_module: Generator,
               file: ^types_file,
               struct_module: nil,
               message: {:mkdir_output_folder, :enomem}
             } = Generator.generate(types_file, code_path, FailingMkdirFile)
    end

    @tag types_content: %{
           Module => %{first: [quote(do: integer())], second: [quote(do: float())]},
           Some.Nested.Module1 => %{former: [quote(do: integer())]}
         }
    test "writes Verififactor source code to code_path for each module from types file", %{
      types_file: types_file,
      code_path: code_path
    } do
      assert {:ok, _paths} = Generator.generate(types_file, code_path)

      type_ensurer_path = Path.join(code_path, "/module_type_ensurer.ex")
      %File.Stat{size: size} = File.stat!(type_ensurer_path)
      assert size > 0

      type_ensurer1_path = Path.join(code_path, "/some_nested_module1_type_ensurer.ex")
      %File.Stat{size: size1} = File.stat!(type_ensurer1_path)
      assert size1 > 0
    end

    @tag types_content: %{
           Module => %{first: [quote(do: integer())], second: [quote(do: float())]},
           Some.Nested.Module1 => %{former: [quote(do: integer())]}
         }
    test "returns list of TypeEnsurer modules source code file paths", %{
      types_file: types_file,
      code_path: code_path
    } do
      type_ensurer_path = Path.join(code_path, "/module_type_ensurer.ex")
      type_ensurer1_path = Path.join(code_path, "/some_nested_module1_type_ensurer.ex")

      assert {:ok,
              [
                type_ensurer_path,
                type_ensurer1_path
              ]} == Generator.generate(types_file, code_path)
    end

    @tag types_content: nil
    test "returns error if read of types file failed", %{
      types_file: types_file,
      code_path: code_path
    } do
      refute File.exists?(types_file)

      assert %Error{
               compiler_module: Generator,
               file: ^types_file,
               struct_module: nil,
               message: {:read_types, :enoent}
             } = Generator.generate(types_file, code_path)
    end

    test "returns error if the content of the types file is corrupted", %{
      types_file: types_file,
      code_path: code_path
    } do
      defmodule FailingTypesFile do
        def mkdir_p(_path), do: :ok

        def read(_path) do
          {:ok, <<0>>}
        end
      end

      assert %Error{
               compiler_module: Generator,
               file: ^types_file,
               struct_module: nil,
               message: {:decode_types_file, :malformed_binary}
             } = Generator.generate(types_file, code_path, FailingTypesFile)
    end

    test "returns error if write of the TypeEnsurer source code to code_path failed", %{
      types_file: types_file,
      code_path: code_path
    } do
      defmodule FailingWriteFile do
        def mkdir_p(_path), do: :ok

        def read(_path) do
          {:ok,
           :erlang.term_to_binary(%{
             Some.Nested.Module1 => %{former: [quote(do: integer())]}
           })}
        end

        def write(_path, _content), do: {:error, :eaccess}
      end

      expected_type_ensurer_path = "#{code_path}/some_nested_module1_type_ensurer.ex"

      assert %Error{
               compiler_module: Generator,
               file: ^expected_type_ensurer_path,
               struct_module: Some.Nested.Module1,
               message: {:write_type_ensurer_module, :eaccess}
             } = Generator.generate(types_file, code_path, FailingWriteFile)
    end
  end

  test "do_type_ensurer_module/2 generates TypeEnsurer module in the form of quoted code" do
    assert {:defmodule, _context,
            [{:__aliases__, [alias: false], [:ParentModule, :TypeEnsurer]} | _tail]} =
             Generator.do_type_ensurer_module(ParentModule, %{first: [quote(do: integer())]})
  end

  test "compile/1 bypasses paths to Elixir.ParallelCompiler" do
    allow Kernel.ParallelCompiler.compile_to_path(any(), any(), any()), return: {:ok, [], []}

    Generator.compile(["path1", "path2"])

    assert_called Kernel.ParallelCompiler.compile_to_path(
                    ["path1", "path2"],
                    is(fn path -> String.ends_with?(path, "_build/test/lib/domo/ebin") end),
                    any()
                  )
  end
end
