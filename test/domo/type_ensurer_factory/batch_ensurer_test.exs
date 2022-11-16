defmodule Domo.TypeEnsurerFactory.BatchEnsurerTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.BatchEnsurer
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  import ResolverTestHelper

  setup_all do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(tmp_path())

    on_exit(fn ->
      File.rm_rf(tmp_path())
      Code.compiler_options(ignore_module_conflict: false)
    end)

    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: false
    disable_raise_in_test_env()
    DomoMixTask.start_plan_collection()

    # Evaluate modules to prepare plan file for domo mix task
    Code.eval_file("test/struct_modules/lib/custom_struct_using_domo.ex")

    DomoMixTask.process_plan({:ok, []}, [])
    enable_raise_in_test_env()

    :ok
  end

  setup [:setup_project_planner]

  @source_dir tmp_path("/#{__MODULE__}")
  @moduletag touch_paths: []

  setup tags do
    File.mkdir_p!(@source_dir)

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

    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: false

    :ok
  end

  describe "BatchEnsurer should" do
    test "return the error if no plan file is found", %{plan_file: plan_file} do
      assert {:error,
              [
                %Error{
                  compiler_module: BatchEnsurer,
                  file: ^plan_file,
                  struct_module: nil,
                  message: :no_plan
                }
              ]} = BatchEnsurer.ensure_struct_integrity(plan_file)
    end

    test "return the error if no fields in plan are found", %{plan_file: plan_file} do
      File.write!(plan_file, :erlang.term_to_binary(%{}))

      assert {:error,
              [
                %Error{
                  compiler_module: BatchEnsurer,
                  file: ^plan_file,
                  struct_module: nil,
                  message: {:no_field_in_plan, :structs_to_ensure}
                }
              ]} = BatchEnsurer.ensure_struct_integrity(plan_file)

      assert {:error,
              [
                %Error{
                  compiler_module: BatchEnsurer,
                  file: ^plan_file,
                  struct_module: nil,
                  message: {:no_field_in_plan, :struct_defaults_to_ensure}
                }
              ]} = BatchEnsurer.ensure_struct_defaults(plan_file)
    end

    test "return :ok when giving structures matching their types", %{
      planner: planner,
      plan_file: plan_file
    } do
      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: "hello"],
        "/some_caller_module.ex",
        9
      )

      flush(planner)

      assert :ok == BatchEnsurer.ensure_struct_integrity(plan_file)
    end

    test "return error with a first structure not matching its type", %{
      planner: planner,
      plan_file: plan_file
    } do
      file = Path.join(@source_dir, "/some_caller_module.ex")

      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: :hello],
        file,
        9
      )

      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: :world],
        file,
        12
      )

      flush(planner)

      assert {:error, {^file, 9, message}} = BatchEnsurer.ensure_struct_integrity(plan_file)

      assert message =~ "CustomStructUsingDomo"
      assert message =~ "Invalid value :hello for field :title of %CustomStructUsingDomo{}."
    end

    @first_path Path.join(@source_dir, "/some_caller_module.ex")
    @second_path Path.join(@source_dir, "/other_caller_module.ex")
    @third_path Path.join(@source_dir, "/third_caller_module.ex")
    @tag touch_paths: [@first_path, @second_path, @third_path]
    test "touch files using struct not matching its type at compile time", %{
      planner: planner,
      plan_file: plan_file
    } do
      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: "hello"],
        @first_path,
        9
      )

      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: :hello],
        @second_path,
        10
      )

      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: :world],
        @third_path,
        12
      )

      flush(planner)

      some_mtime = mtime(@first_path)
      other_mtime = mtime(@second_path)
      third_mtime = mtime(@third_path)

      BatchEnsurer.ensure_struct_integrity(plan_file)

      assert mtime(@first_path) == some_mtime
      assert mtime(@second_path) > other_mtime
      assert mtime(@third_path) > third_mtime
    end

    test "does not touch nonexisting files", %{
      planner: planner,
      plan_file: plan_file
    } do
      plan_struct_integrity_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: :world],
        "src/elixir_compiler.erl",
        9
      )

      flush(planner)

      BatchEnsurer.ensure_struct_integrity(plan_file)
    end

    @first_path Path.join(@source_dir, "/some_caller_module.ex")
    @second_path Path.join(@source_dir, "/other_caller_module.ex")
    @third_path Path.join(@source_dir, "/third_caller_module.ex")
    @tag touch_paths: [@first_path, @second_path, @third_path]
    test "touch files having field's default value not matching its type", %{
      planner: planner,
      plan_file: plan_file
    } do
      plan_struct_defaults_ensurance(
        planner,
        CustomStructUsingDomo,
        [title: "hello"],
        @first_path,
        8
      )

      plan_struct_defaults_ensurance(
        planner,
        Recipient,
        [title: "hello"],
        @second_path,
        9
      )

      plan_struct_defaults_ensurance(
        planner,
        RecipientWarnOverriden,
        [title: "world"],
        @third_path,
        11
      )

      flush(planner)

      some_mtime = mtime(@first_path)
      other_mtime = mtime(@second_path)
      third_mtime = mtime(@third_path)

      BatchEnsurer.ensure_struct_defaults(plan_file)

      assert mtime(@first_path) == some_mtime
      assert mtime(@second_path) > other_mtime
      assert mtime(@third_path) > third_mtime
    end
  end

  defp mtime(path) do
    %File.Stat{mtime: mtime} = File.stat!(path, time: :posix)
    mtime
  end
end
