defmodule Domo.TypeEnsurerFactory.DependencyResolverTest do
  use Domo.FileCase
  use Placebo

  alias Domo.TypeEnsurerFactory.DependencyResolver.ElixirTask
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error

  @source_dir tmp_path("/#{__MODULE__}")

  @module_path1 Path.join(@source_dir, "/module_path1.ex")
  @module_path2 Path.join(@source_dir, "/module_path2.ex")
  @module_path3 Path.join(@source_dir, "/module_path3.ex")
  @reference_path Path.join(@source_dir, "/reference_path.ex")

  @deps_path Path.join(@source_dir, "/deps.dat")

  @moduletag deps: %{}
  @moduletag touch_paths: []

  setup tags do
    File.mkdir_p!(@source_dir)
    File.write!(@deps_path, :erlang.term_to_binary(tags.deps))

    # December 11, 2018
    base_time = 1_544_519_753

    for {path, idx} <- Enum.with_index(tags.touch_paths) do
      time_seconds = base_time + idx
      File.touch!(path, time_seconds)

      time_seconds
    end

    on_exit(fn ->
      Enum.each(tags.touch_paths, &File.rm/1)
      File.rm_rf(@source_dir)
    end)

    on_exit(fn ->
      ResolverTestHelper.stop_project_palnner()
    end)

    :ok
  end

  describe "Dependency Resolver should" do
    test "return ok giving no deps file, that is Domo is not used" do
      deps_path = tmp_path("nonexistent.dat")
      refute File.exists?(deps_path)

      assert {:ok, []} = DependencyResolver.maybe_recompile_depending_structs(deps_path, [])
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
             } =
               DependencyResolver.maybe_recompile_depending_structs(deps_path,
                 file_module: FailingTypesFile
               )
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {CustomStruct, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
              ]},
           Recipient =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct)}
              ]}
         }
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "touch and recompile depending module giving md5 hash of dependant module types mismatching one from deps file" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      assert mtime(@module_path1) < mtime(@module_path2)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, [])

      assert mtime(@module_path1) > mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           EmptyStruct =>
             {@module_path1,
              [
                {CustomStruct, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
              ]},
           Location =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct)}
              ]},
           Recipient =>
             {@module_path3,
              [
                {Location, ModuleInspector.beam_types_hash(Location)}
              ]}
         }
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @module_path3,
           @reference_path
         ]
    test "touch and recompile depending module if dependant modules have been recompiled" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}
      assert mtime(@module_path1) < mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      assert mtime(@module_path3) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, [])

      assert mtime(@module_path1) > mtime(@reference_path)
      assert mtime(@module_path2) > mtime(@reference_path)
      assert mtime(@module_path3) > mtime(@reference_path)

      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
              ]},
           NonexistingModule2 =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct)}
              ]}
         }
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "remove unloadable modules and recompile modules that being depending" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}
      assert mtime(@module_path1) < mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, [])

      assert @deps_path
             |> File.read!()
             |> :erlang.binary_to_term() == %{
               Location => {@module_path1, []}
             }

      assert mtime(@module_path1) > mtime(@reference_path)
      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {EmptyStruct, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
              ]},
           Recipient =>
             {@module_path1,
              [
                {Location, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
              ]}
         }
    @tag touch_paths: [@module_path1]
    test "compile file only once even if multiple modules there to be recompiled" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, [])

      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [{NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}]}
         }
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
               message: {:update_deps, :enoent}
             } =
               DependencyResolver.maybe_recompile_depending_structs(deps_path,
                 file_module: WriteFailingFile
               )
    end

    test "return ok giving no modules eligible for recompilation" do
      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path, []) ==
               {:ok, []}
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [{NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}]}
         }
    test "bypass compilation error" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:error, [:err], []}

      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path, []) ==
               {:error, [:err], []}
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [{NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}]}
         }
    test "bypass compilation success" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [:module], [:warn]}

      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path, []) ==
               {:ok, [:module], [:warn]}
    end
  end

  defp mtime(path) do
    %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
    mtime
  end
end
