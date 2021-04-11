defmodule Domo.TypeEnsurerFactory.DependencyResolverTest do
  use Domo.FileCase
  use Placebo

  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error
  alias Kernel.ParallelCompiler

  @source_dir tmp_path("/#{__MODULE__}")
  @compile_path Mix.Project.compile_path()

  @dependant1_beam_path Path.join([@compile_path, "Elixir.DependantItem1.beam"])
  @dependant2_beam_path Path.join([@compile_path, "Elixir.DependantItem2.beam"])

  @depending1_path Path.join(@source_dir, "/depending_module1.ex")
  @depending1_beam_path Path.join([@compile_path, "Elixir.DependingModule1.beam"])

  @depending2_path Path.join(@source_dir, "/depending_module2.ex")
  @depending2_beam_path Path.join([@compile_path, "Elixir.DependingModule2.beam"])

  @deps_path Path.join(@source_dir, "/deps.dat")

  @moduletag deps: %{}
  @moduletag touch_paths: []

  setup tags do
    File.mkdir_p!(@source_dir)
    File.write!(@deps_path, :erlang.term_to_binary(tags.deps))

    file_times =
      for {path, idx} <- Enum.with_index(tags.touch_paths) do
        time_seconds = 1_544_519_753 + idx
        File.touch!(path, time_seconds)

        time_seconds
      end

    last_file_time = List.last(file_times)

    on_exit(fn ->
      Enum.each(tags.touch_paths, &File.rm/1)
      File.rm_rf(@source_dir)
    end)

    on_exit(fn ->
      ResolverTestHelper.stop_project_palnner()
    end)

    {:ok, last_file_time: last_file_time}
  end

  describe "Dependency Resolver should" do
    test "return :ok if the deps file is not found, that is Domo is not used" do
      deps_path = tmp_path("nonexistent.dat")
      refute File.exists?(deps_path)

      assert {:ok, [], []} = DependencyResolver.maybe_recompile_depending_structs(deps_path)
    end

    test "return error if the content of the deps file is corrupted" do
      defmodule FailingTypesFile do
        def read(_path), do: {:ok, <<0>>}
      end

      deps_path = tmp_path("nonexistent.dat")

      assert %Error{
               compiler_module: DependencyResolver,
               file: ^deps_path,
               struct_module: nil,
               message: {:decode_deps, :malformed_binary}
             } = DependencyResolver.maybe_recompile_depending_structs(deps_path, FailingTypesFile)
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem1, DependantItem2]},
           DependingModule2 => {@depending2_path, [DependantItem2]}
         }
    @tag touch_paths: [
           @dependant2_beam_path,
           @depending1_path,
           @depending1_beam_path,
           @depending2_path,
           @depending2_beam_path,
           @dependant1_beam_path,
           @deps_path
         ]
    test """
    touch and recompile the depending modules that have beam files modified \
    earlier then dependant beam files
    """ do
      allow ParallelCompiler.compile(any()), return: {:ok, [], []}
      depending1_mtime = mtime(@depending1_path)
      depending2_mtime = mtime(@depending2_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path)

      assert mtime(@depending2_path) == depending2_mtime
      assert mtime(@depending1_path) > depending1_mtime
      assert_called ParallelCompiler.compile([@depending1_path])
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem1, DependantItem2]},
           DependingModule2 => {@depending2_path, [DependantItem2]}
         }
    @tag touch_paths: [
           @dependant1_beam_path,
           @depending1_path,
           @depending1_beam_path,
           @depending2_path,
           @depending2_beam_path,
           @deps_path
         ]
    test "touch and recompile depending module if any dependant module's beam file is not found" do
      allow ParallelCompiler.compile(any()), return: {:ok, [], []}
      depending1_mtime = mtime(@depending1_path)
      depending2_mtime = mtime(@depending2_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path)

      assert mtime(@depending1_path) > depending1_mtime
      assert mtime(@depending2_path) > depending2_mtime

      assert_called ParallelCompiler.compile([@depending2_path, @depending1_path])
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem2]},
           DependingModule2 => {@depending1_path, [DependantItem2]}
         }
    @tag touch_paths: [
           @depending1_path,
           @depending1_beam_path,
           @depending2_beam_path,
           @dependant2_beam_path,
           @deps_path
         ]
    test "compile file only once even if multiple modules there to be recompiled" do
      allow ParallelCompiler.compile(any()), return: {:ok, [], []}

      DependencyResolver.maybe_recompile_depending_structs(@deps_path)

      assert_called ParallelCompiler.compile([@depending1_path])
    end

    @tag deps: %{DependingModule1 => {@depending1_path, [DependantItem1]}}
    @tag touch_paths: [@depending1_path, @dependant1_beam_path, @deps_path]
    test "raise an file error if depending module's beam file is not found" do
      beam_file_regex = Regex.compile!(".*#{@depending1_beam_path}.*")

      assert_raise File.Error, beam_file_regex, fn ->
        DependencyResolver.maybe_recompile_depending_structs(@deps_path)
      end
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem1, DependantItem2]},
           DependingModule2 => {@depending2_path, [DependantItem2]}
         }
    @tag touch_paths: [
           @dependant1_beam_path,
           @dependant2_beam_path,
           @depending2_path,
           @depending2_beam_path,
           @deps_path
         ]
    test "remove depending module from deps list if it's source file is not found" do
      DependencyResolver.maybe_recompile_depending_structs(@deps_path)

      assert @deps_path
             |> File.read!()
             |> :erlang.binary_to_term() == %{
               DependingModule2 => {@depending2_path, [DependantItem2]}
             }
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem1, DependantItem2]},
           DependingModule2 => {@depending2_path, [DependantItem2]}
         }
    @tag touch_paths: [
           @dependant1_beam_path,
           @dependant2_beam_path,
           @depending2_path,
           @depending2_beam_path,
           @deps_path
         ]
    test "keep the mtime of deps file after update" do
      deps_mtime = mtime(@deps_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path)

      assert mtime(@deps_path) == deps_mtime
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem1, DependantItem2]},
           DependingModule2 => {@depending2_path, [DependantItem2]}
         }
    @tag touch_paths: [
           @dependant1_beam_path,
           @dependant2_beam_path,
           @depending2_path,
           @depending2_beam_path,
           @deps_path
         ]
    test "return error if can't write deps file" do
      defmodule WriteFailingFile do
        def read(path), do: File.read(path)
        def write(_path, _content), do: {:error, :enoent}
      end

      deps_path = @deps_path

      assert %Error{
               compiler_module: DependencyResolver,
               file: ^deps_path,
               struct_module: nil,
               message: {:upd_deps, :enoent}
             } = DependencyResolver.maybe_recompile_depending_structs(deps_path, WriteFailingFile)
    end

    @tag deps: %{
           DependingModule1 => {@depending1_path, [DependantItem1, DependantItem2]}
         }
    @tag touch_paths: [
           @dependant2_beam_path,
           @depending1_path,
           @deps_path,
           @depending1_beam_path,
           @dependant1_beam_path
         ]
    test "does Not touch or recompile the modules having beam files modified later then the deps file" do
      allow ParallelCompiler.compile(any()), return: {:ok, [], []}
      depending1_mtime = mtime(@depending1_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path)

      assert mtime(@depending1_path) == depending1_mtime
      refute_called(ParallelCompiler.compile([@depending1_path]))
    end

    test "bypass compilation error" do
      allow ParallelCompiler.compile(any()), return: {:error, [:err], []}

      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path) ==
               {:error, [:err], []}
    end

    test "bypass compilation success" do
      allow ParallelCompiler.compile(any()), return: {:ok, [:module], [:warn]}

      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path) ==
               {:ok, [:module], [:warn]}
    end
  end

  defp mtime(path) do
    %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
    mtime
  end
end
