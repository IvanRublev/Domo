defmodule Domo.TypeEnsurerFactory.ResolvePlannerTest do
  use Domo.FileCase

  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias Domo.MixProjectHelper
  alias Domo.TypeEnsurerFactory.ResolvePlanner

  describe "ResolvePlanner for sake of start should" do
    test "be started once for a plan file" do
      plan_path = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)

      {:ok, pid} = ResolvePlanner.start(plan_path)

      on_exit(fn ->
        GenServer.stop(pid)
      end)

      assert {:error, {:already_started, pid}} == ResolvePlanner.start(plan_path)

      name = ResolvePlanner.via(plan_path)
      assert pid == GenServer.whereis(name)
    end

    test "return same {:ok, pid} answer if already started" do
      plan_path = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)
      {:ok, pid} = ResolvePlanner.ensure_started(plan_path)

      on_exit(fn ->
        GenServer.stop(pid)
      end)

      assert {:error, {:already_started, pid}} == ResolvePlanner.start(plan_path)

      assert {:ok, pid} == ResolvePlanner.ensure_started(plan_path)
    end
  end

  test "ResolvePlanner should return that its compile when it is running" do
    # stop global server that may run due to compilation of structs
    project = MixProjectHelper.global_stub()
    plan_path = DomoMixTask.manifest_path(project, :plan)
    ResolvePlanner.stop(plan_path)

    assert ResolvePlanner.compile_time?() == false

    plan_path = "some_path_1"
    {:ok, _pid} = ResolvePlanner.start(plan_path)

    assert ResolvePlanner.compile_time?() == true

    ResolvePlanner.stop(plan_path)

    assert ResolvePlanner.compile_time?() == false
  end

  describe "ResolvePlanner for sake of planning should" do
    @describetag start_server: true

    setup tags do
      plan_file = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)

      if tags.start_server do
        {:ok, pid} = ResolvePlanner.start(plan_file)

        on_exit(fn ->
          GenServer.stop(pid)
        end)
      end

      %{plan_file: plan_file}
    end

    test "accept struct field's type for the resolve plan", %{plan_file: plan_file} do
      assert :ok ==
               ResolvePlanner.plan_types_resolving(
                 plan_file,
                 TwoFieldStruct,
                 :first,
                 quote(do: integer)
               )
    end

    test "accept empty struct for the resolve plan", %{plan_file: plan_file} do
      assert :ok == ResolvePlanner.plan_empty_struct(plan_file, TwoFieldStruct)
    end

    test "accept struct module's environment for further remote types resolve", %{
      plan_file: plan_file
    } do
      assert :ok == ResolvePlanner.keep_module_environment(plan_file, TwoFieldStruct, __ENV__)
    end

    test "accept struct fields for postponed integrity ensurance", %{plan_file: plan_file} do
      assert :ok ==
               ResolvePlanner.plan_struct_integrity_ensurance(
                 plan_file,
                 TwoFieldStruct,
                 [title: "Hello", duration: 15],
                 "/module_path.ex",
                 9
               )
    end

    test "be able to flush all planned types to disk", %{plan_file: plan_file} do
      ResolvePlanner.plan_types_resolving(
        plan_file,
        TwoFieldStruct,
        :first,
        quote(do: integer)
      )

      ResolvePlanner.plan_types_resolving(
        plan_file,
        TwoFieldStruct,
        :second,
        quote(do: float)
      )

      ResolvePlanner.plan_types_resolving(
        plan_file,
        IncorrectDefault,
        :second,
        quote(do: Generator.a_str())
      )

      ResolvePlanner.plan_empty_struct(
        plan_file,
        EmptyStruct
      )

      env = __ENV__
      ResolvePlanner.keep_module_environment(plan_file, TwoFieldStruct, env)

      ResolvePlanner.plan_struct_integrity_ensurance(
        plan_file,
        TwoFieldStruct,
        [title: "Hello", duration: 15],
        "/module_path.ex",
        9
      )

      assert :ok == ResolvePlanner.flush(plan_file)

      plan =
        plan_file
        |> File.read!()
        |> :erlang.binary_to_term()

      assert %{
               filed_types_to_resolve: %{
                 TwoFieldStruct => %{first: quote(do: integer), second: quote(do: float)},
                 IncorrectDefault => %{second: quote(do: Generator.a_str())},
                 EmptyStruct => %{}
               },
               environments: %{TwoFieldStruct => env},
               structs_to_ensure: [
                 {TwoFieldStruct, [title: "Hello", duration: 15], "/module_path.ex", 9}
               ]
             } == plan
    end

    test "refute to add a struct field's type to plan twice", %{plan_file: plan_file} do
      ResolvePlanner.plan_types_resolving(
        plan_file,
        TwoFieldStruct,
        :first,
        quote(do: integer)
      )

      res =
        ResolvePlanner.plan_types_resolving(
          plan_file,
          TwoFieldStruct,
          :first,
          quote(do: atom)
        )

      assert {:error, :field_exists} == res
    end

    @tag start_server: false
    test "be able to merge made plan with the plan from disk", %{plan_file: plan_file} do
      incorrect_default_env = %{__ENV__ | module: IncorrectDefault}

      plan_binary =
        :erlang.term_to_binary(%{
          filed_types_to_resolve: %{IncorrectDefault => %{second: quote(do: Generator.a_str())}},
          environments: %{IncorrectDefault => incorrect_default_env},
          structs_to_ensure: [
            {TwoFieldStruct, [title: "Hello", duration: 15], "/module_path.ex", 9}
          ]
        })

      File.write!(plan_file, plan_binary)

      {:ok, pid} = ResolvePlanner.start(plan_file)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      ResolvePlanner.plan_types_resolving(
        plan_file,
        TwoFieldStruct,
        :first,
        quote(do: integer)
      )

      env = __ENV__
      ResolvePlanner.keep_module_environment(plan_file, TwoFieldStruct, env)

      ResolvePlanner.plan_struct_integrity_ensurance(
        plan_file,
        TwoFieldStruct,
        [title: "World", duration: 20],
        "/other_module_path.ex",
        12
      )

      assert :ok == ResolvePlanner.flush(plan_file)

      plan =
        plan_file
        |> File.read!()
        |> :erlang.binary_to_term()

      assert %{
               filed_types_to_resolve: %{
                 TwoFieldStruct => %{first: quote(do: integer)},
                 IncorrectDefault => %{second: quote(do: Generator.a_str())}
               },
               environments: %{
                 TwoFieldStruct => env,
                 IncorrectDefault => incorrect_default_env
               },
               structs_to_ensure: [
                 {TwoFieldStruct, [title: "Hello", duration: 15], "/module_path.ex", 9},
                 {TwoFieldStruct, [title: "World", duration: 20], "/other_module_path.ex", 12}
               ]
             } == plan
    end
  end

  describe "ResolvePlanner for sake of stop should" do
    setup do
      plan_path = DomoMixTask.manifest_path(MixProjectStubCorrect, :plan)
      {:ok, plan_path: plan_path}
    end

    test "flush the plan and stop", %{plan_path: plan_path} do
      {:ok, pid} = ResolvePlanner.start(plan_path)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      assert :ok = ResolvePlanner.ensure_flushed_and_stopped(plan_path)

      refute Process.alive?(pid)
      assert File.exists?(plan_path)
    end

    test "Not flush and stop if already stopped", %{plan_path: plan_path} do
      assert :ok == ResolvePlanner.ensure_flushed_and_stopped(plan_path)
    end

    test "stop without flush", %{plan_path: plan_path} do
      {:ok, pid} = ResolvePlanner.start(plan_path)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      assert :ok == ResolvePlanner.stop(plan_path)
      refute Process.alive?(pid)
    end

    test "Not stop if already stopped", %{plan_path: plan_path} do
      assert :ok == ResolvePlanner.stop(plan_path)
    end
  end
end
