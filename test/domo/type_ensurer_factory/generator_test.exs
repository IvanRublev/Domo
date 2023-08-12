defmodule Domo.TypeEnsurerFactory.GeneratorTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.TermSerializer
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Generator
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  import GeneratorTestHelper

  @moduletag types_content: %{}
  @moduletag ecto_assocs_content: %{}

  setup tags do
    project = MixProjectStubCorrect
    types_file = DomoMixTask.manifest_path(project, :types)
    ecto_assocs_file = DomoMixTask.manifest_path(project, :ecto_assocs)
    t_reflections_file = DomoMixTask.manifest_path(project, :t_reflections)
    code_path = DomoMixTask.generated_code_path(project)

    types_content = tags.types_content

    unless is_nil(types_content) do
      File.write!(types_file, TermSerializer.term_to_binary(types_content))
    end

    ecto_assocs_content = tags.ecto_assocs_content

    unless is_nil(ecto_assocs_content) do
      File.write!(ecto_assocs_file, TermSerializer.term_to_binary(ecto_assocs_content))
    end

    File.write!(t_reflections_file, TermSerializer.term_to_binary(%{}))

    on_exit(fn ->
      _ = File.rm(types_file)
      _ = File.rm(ecto_assocs_file)
      _ = File.rm(t_reflections_file)
    end)

    %{types_file: types_file, ecto_assocs_file: ecto_assocs_file, t_reflections_file: t_reflections_file, code_path: code_path}
  end

  describe "generate/2" do
    test "makes code directory", %{types_file: types_file, ecto_assocs_file: ecto_assocs_file, t_reflections_file: t_reflections_file, code_path: code_path} do
      File.rm_rf(code_path)

      Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path)
      assert true == File.exists?(code_path)
    end

    test "returns error if make of the directory failed", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      defmodule FailingMkdirFile do
        def mkdir_p(_path), do: {:error, :enomem}
      end

      assert %Error{
               compiler_module: Generator,
               file: ^code_path,
               struct_module: nil,
               message: {:mkdir_output_folder, :enomem}
             } = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path, FailingMkdirFile)
    end

    @tag types_content: types_by_module_content(%{
           Module => %{first: [quote(do: integer())], second: [quote(do: float())]},
           Some.Nested.Module1 => %{former: [quote(do: integer())]},
           EmptyStruct => %{}
         })
    test "writes TypeEnsurer source code to code_path for each module from types file", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      assert {:ok, _paths} = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path)

      type_ensurer_path = Path.join(code_path, "/module_type_ensurer.ex")
      %File.Stat{size: size} = File.stat!(type_ensurer_path)
      assert size > 0

      type_ensurer1_path = Path.join(code_path, "/some_nested_module1_type_ensurer.ex")
      %File.Stat{size: size1} = File.stat!(type_ensurer1_path)
      assert size1 > 0

      type_ensurer2_path = Path.join(code_path, "/empty_struct_type_ensurer.ex")
      %File.Stat{size: size2} = File.stat!(type_ensurer2_path)
      assert size2 > 0
    end

    @tag types_content: types_by_module_content(%{
           Module => %{first: [quote(do: integer())], second: [quote(do: float())]},
           Some.Nested.Module1 => %{former: [quote(do: integer())]},
           EmptyStruct => %{}
         })
    test "returns list of TypeEnsurer modules source code file paths", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      type_ensurer_path = Path.join(code_path, "/module_type_ensurer.ex")
      type_ensurer1_path = Path.join(code_path, "/some_nested_module1_type_ensurer.ex")
      type_ensurer2_path = Path.join(code_path, "/empty_struct_type_ensurer.ex")

      assert {:ok, list} = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path)
      assert [
        type_ensurer2_path,
        type_ensurer_path,
        type_ensurer1_path
      ] == Enum.sort(list)
    end

    @tag types_content: nil
    test "returns error if read of types file failed", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      refute File.exists?(types_file)

      assert %Error{
               compiler_module: Generator,
               file: ^types_file,
               struct_module: nil,
               message: {:read_types, :enoent}
             } = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path)
    end

    @tag types_content: types_by_module_content(%{
      Module => %{first: [quote(do: integer())], second: [quote(do: float())]},
      Some.Nested.Module1 => %{former: [quote(do: integer())]},
      EmptyStruct => %{}
    })
    @tag ecto_assocs_content: nil
    test "returns error if read of ecto assocs file failed", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      refute File.exists?(ecto_assocs_file)

      assert %Error{
               compiler_module: Generator,
               file: ^ecto_assocs_file,
               struct_module: nil,
               message: {:read_ecto_assocs, :enoent}
             } = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path)
    end

    test "returns error if the content of the types file is corrupted", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
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
             } = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path, FailingTypesFile)
    end

    test "returns error if the content of the ecto assocs file is corrupted", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      defmodule FailingEctoAssocsFile do
        def mkdir_p(_path), do: :ok

        @types_file types_file

        def read(@types_file) do
          {:ok, TermSerializer.term_to_binary(%{})}
        end

        def read(_path) do
          {:ok, <<0>>}
        end
      end

      assert %Error{
               compiler_module: Generator,
               file: ^ecto_assocs_file,
               struct_module: nil,
               message: {:decode_ecto_assocs_file, :malformed_binary}
             } = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path, FailingEctoAssocsFile)
    end

    test "returns error if write of the TypeEnsurer source code to code_path failed", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file,
      code_path: code_path
    } do
      defmodule FailingWriteFile do
        def mkdir_p(_path), do: :ok

        def read(_path) do
          {:ok,
           TermSerializer.term_to_binary(types_by_module_content(%{
             Some.Nested.Module1 => %{former: [quote(do: integer())]}
           }))}
        end

        def write(_path, _content), do: {:error, :eaccess}
      end

      expected_type_ensurer_path = "#{code_path}/some_nested_module1_type_ensurer.ex"

      assert %Error{
               compiler_module: Generator,
               file: ^expected_type_ensurer_path,
               struct_module: Some.Nested.Module1,
               message: {:write_type_ensurer_module, :eaccess}
             } = Generator.generate(types_file, ecto_assocs_file, t_reflections_file, code_path, FailingWriteFile)
    end
  end

  test "generate_one/2 generates TypeEnsurer module in the form of quoted code" do
    assert {:defmodule, _context, [{:__aliases__, [alias: false], [:ParentModule, :TypeEnsurer]} | _tail]} =
             Generator.generate_one(
               ParentModule,
               types_content_empty_precond(%{first: [quote(do: integer())]}),
               [],
               nil
             )
  end

  test "generate_one/2 ignores meta of literal types when generating TypeEnsurer module" do
    assert {:defmodule, _context, [{:__aliases__, [alias: false], [:ParentModule, :TypeEnsurer]} | _tail]} =
             Generator.generate_one(
               ParentModule,
               types_content_empty_precond(%{first: [[{:atom, [closing: [line: 355, column: 51], column: 46], []}]]}),
               [],
               nil
             )
  end

  test "generate_invalid/1 generates invalid TypeEnsurer module in the form of quoted code" do
    assert {:defmodule, _context, [{:__aliases__, [alias: false], [:ParentModule, :TypeEnsurer]} | _tail]} = Generator.generate_invalid(ParentModule)
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
