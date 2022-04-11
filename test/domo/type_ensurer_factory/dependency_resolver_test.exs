defmodule Domo.TypeEnsurerFactory.DependencyResolverTest do
  use Domo.FileCase
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory.DependencyResolver.ElixirTask
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error

  import ResolverTestHelper

  @source_dir tmp_path("/#{__MODULE__}")

  @module_path1 Path.join(@source_dir, "/module_path1.ex")
  @module_path2 Path.join(@source_dir, "/module_path2.ex")
  @module_path3 Path.join(@source_dir, "/module_path3.ex")
  @reference_path Path.join(@source_dir, "/reference_path.ex")

  @deps_path Path.join(@source_dir, "/deps.dat")
  @preconds_path Path.join(@source_dir, "/preconds.dat")

  @moduletag deps: %{}
  @moduletag preconds: %{}
  @moduletag touch_paths: []

  setup tags do
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true
    allow File.rm(any()), meck_options: [:passthrough], return: :ok

    File.mkdir_p!(@source_dir)
    File.write!(@deps_path, :erlang.term_to_binary(tags.deps))
    File.write!(@preconds_path, :erlang.term_to_binary(tags.preconds))

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
      stop_project_palnner()
    end)

    :ok
  end

  describe "Dependency Resolver should" do
    test "return ok giving no deps file, that is Domo is not used" do
      deps_path = tmp_path("nonexistent.dat")
      preconds_path = tmp_path("preconds.dat")
      refute File.exists?(deps_path)

      assert {:ok, []} = DependencyResolver.maybe_recompile_depending_structs(deps_path, preconds_path, [])
    end

    test "return error if the content of the deps file is corrupted" do
      defmodule FailingDepsFile do
        def read(path) do
          if String.ends_with?(path, "/deps.dat") do
            {:ok, <<0>>}
          else
            {:ok, :erlang.term_to_binary(%{})}
          end
        end
      end

      assert %Error{
               compiler_module: DependencyResolver,
               file: @deps_path,
               struct_module: nil,
               message: {:decode_deps, :malformed_binary}
             } = DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, file_module: FailingDepsFile)
    end

    test "return error if the content of the preconds file is corrupted" do
      defmodule FailingPrecondsFile do
        def read(path) do
          if String.ends_with?(path, "/preconds.dat") do
            {:ok, <<0>>}
          else
            {:ok, :erlang.term_to_binary(%{})}
          end
        end
      end

      assert %Error{
               compiler_module: DependencyResolver,
               file: @preconds_path,
               struct_module: nil,
               message: {:decode_preconds, :malformed_binary}
             } = DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, file_module: FailingPrecondsFile)
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {CustomStruct, ModuleInspector.beam_types_hash(CustomStruct), nil}
              ]},
           Recipient =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
              ]}
         }
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "Not touch or recompile modules giving matching types md5 hash" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      assert mtime(@module_path1) < mtime(@module_path2)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert mtime(@module_path1) < mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      refute_called(ElixirTask.recompile_with_elixir(any()))
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {CustomStructWithPrecond, ModuleInspector.beam_types_hash(CustomStructWithPrecond), preconds_hash(title: "fn _arg -> true end")}
              ]},
           Recipient =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
              ]}
         }
    @tag preconds: %{CustomStructWithPrecond => [title: "fn _arg -> true end"]}
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "Not touch or recompile modules giving matching preconds md5 hash" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      assert mtime(@module_path1) < mtime(@module_path2)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert mtime(@module_path1) < mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      refute_called(ElixirTask.recompile_with_elixir(any()))
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {CustomStruct, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}
              ]},
           Recipient =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
              ]}
         }
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "touch, delete BEAM, and recompile depending module giving md5 hash of dependent module types mismatching one from deps file" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      assert mtime(@module_path1) < mtime(@module_path2)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert mtime(@module_path1) > mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      assert_called File.rm(is(&String.ends_with?(&1, "/ebin/Elixir.Location.beam")))
      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {CustomStructWithPrecond, ModuleInspector.beam_types_hash(CustomStructWithPrecond),
                 <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>}
              ]},
           Recipient =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
              ]}
         }
    @tag preconds: %{CustomStructWithPrecond => [title: "fn _arg -> true end"]}
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "touch and recompile depending module giving md5 hash of preconds mismatching one from preconds file" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      assert mtime(@module_path1) < mtime(@module_path2)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert mtime(@module_path1) > mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           EmptyStruct =>
             {@module_path1,
              [
                {CustomStruct, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}
              ]},
           Location =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
              ]},
           Recipient =>
             {@module_path3,
              [
                {Location, ModuleInspector.beam_types_hash(Location), nil}
              ]}
         }
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @module_path3,
           @reference_path
         ]
    test "touch and recompile depending module if dependent modules have been recompiled" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}
      assert mtime(@module_path1) < mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)
      assert mtime(@module_path3) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert mtime(@module_path1) > mtime(@reference_path)
      assert mtime(@module_path2) > mtime(@reference_path)
      assert mtime(@module_path3) > mtime(@reference_path)

      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}
              ]},
           NonexistingModule2 =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
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

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

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
                {CustomStruct, ModuleInspector.beam_types_hash(CustomStruct), preconds_hash(title: "fn _arg -> true end")}
              ]},
           NonexistingModule2 =>
             {@module_path2,
              [
                {EmptyStruct, ModuleInspector.beam_types_hash(EmptyStruct), nil}
              ]}
         }
    @tag preconds: %{CustomStruct => [title: "fn _arg -> true end"]}
    @tag touch_paths: [
           @module_path1,
           @module_path2,
           @reference_path
         ]
    test "remove module from preconds having no precond function and recompile modules that being depending" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}
      assert mtime(@module_path1) < mtime(@reference_path)
      assert mtime(@module_path2) < mtime(@reference_path)

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert @preconds_path
             |> File.read!()
             |> :erlang.binary_to_term() == %{}

      assert mtime(@module_path1) > mtime(@reference_path)
      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {EmptyStruct, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}
              ]},
           Recipient =>
             {@module_path1,
              [
                {Location, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}
              ]}
         }
    @tag touch_paths: [@module_path1]
    test "compile file only once even if multiple modules there to be recompiled" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [], []}

      DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, [])

      assert_called ElixirTask.recompile_with_elixir(any())
    end

    @tag deps: %{Location => {@module_path1, [{NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}]}}
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
               DependencyResolver.maybe_recompile_depending_structs(
                 deps_path,
                 @preconds_path,
                 file_module: WriteFailingFile
               )
    end

    @tag deps: %{
           Location =>
             {@module_path1,
              [
                {
                  CustomStruct,
                  ModuleInspector.beam_types_hash(CustomStructWithPrecond),
                  preconds_hash(title: "fn _arg -> true end")
                }
              ]}
         }
    @tag preconds: %{CustomStruct => [title: "fn _arg -> true end"]}
    test "return error if can't write preconds file" do
      defmodule WriteFailingPrecondsFile do
        def read(path), do: File.read(path)

        def write(path, _content) do
          if String.ends_with?(path, "/preconds.dat") do
            {:error, :enoent}
          else
            :ok
          end
        end
      end

      preconds_path = @preconds_path

      assert %Error{
               compiler_module: DependencyResolver,
               file: ^preconds_path,
               struct_module: nil,
               message: {:update_preconds, :enoent}
             } =
               DependencyResolver.maybe_recompile_depending_structs(
                 @deps_path,
                 preconds_path,
                 file_module: WriteFailingPrecondsFile
               )
    end

    test "return ok giving no modules eligible for recompilation" do
      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, []) ==
               {:ok, []}
    end

    @tag deps: %{Location => {@module_path1, [{NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}]}}
    test "bypass compilation error" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:error, [:err], []}

      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, []) ==
               {:error, [:err], []}
    end

    @tag deps: %{Location => {@module_path1, [{NonexistingModule1, <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>, nil}]}}
    test "bypass compilation success" do
      allow ElixirTask.recompile_with_elixir(any()), return: {:ok, [:module], [:warn]}

      assert DependencyResolver.maybe_recompile_depending_structs(@deps_path, @preconds_path, []) ==
               {:ok, [:module], [:warn]}
    end
  end

  defp mtime(path) do
    %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
    mtime
  end
end
