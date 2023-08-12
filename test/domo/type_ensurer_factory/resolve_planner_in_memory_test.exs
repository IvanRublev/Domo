defmodule Domo.TypeEnsurerFactory.ResolvePlannerInMemoryTest do
  use Domo.FileCase

  alias Domo.TypeEnsurerFactory.ResolvePlanner

  describe "ResolvePlanner for sake of start should" do
    setup do
      on_exit(fn ->
        ResolverTestHelper.stop_in_memory_planner()
      end)

      :ok
    end

    test "be started once" do
      {:ok, pid} = ResolvePlanner.start(:in_memory, :in_memory, [])

      assert {:error, {:already_started, pid}} == ResolvePlanner.start(:in_memory, :in_memory, [])

      name = ResolvePlanner.via(:in_memory)
      assert pid == GenServer.whereis(name)
    end

    test "return same {:ok, pid} answer if already started" do
      {:ok, pid} = ResolvePlanner.ensure_started(:in_memory, :in_memory, [])

      assert {:error, {:already_started, pid}} == ResolvePlanner.start(:in_memory, :in_memory, [])

      assert {:ok, pid} == ResolvePlanner.ensure_started(:in_memory, :in_memory, [])
    end

    test "shutdown after parent process dies" do
      parent_pid =
        spawn(fn ->
          ResolvePlanner.ensure_started(:in_memory, :in_memory, [])
        end)

      Process.monitor(parent_pid)

      assert_receive {:DOWN, _, :process, ^parent_pid, _}
      name = ResolvePlanner.via(:in_memory)
      refute GenServer.whereis(name)
    end
  end

  describe "ResolvePlanner for sake of planning should" do
    @describetag start_server: true

    setup tags do
      if tags.start_server do
        {:ok, pid} = ResolvePlanner.start(:in_memory, :in_memory, [])

        on_exit(fn ->
          ResolverTestHelper.stop_gen_server(pid)
        end)
      end

      :ok
    end

    test "accept struct field's type for the resolve plan" do
      assert :ok ==
               ResolvePlanner.plan_types_resolving(
                 :in_memory,
                 TwoFieldStruct,
                 :first,
                 quote(do: integer)
               )
    end

    test "accept empty struct for the resolve plan" do
      assert :ok == ResolvePlanner.plan_empty_struct(:in_memory, TwoFieldStruct)
    end

    test "accept struct module's environment for further remote types resolve" do
      assert :ok == ResolvePlanner.keep_module_environment(:in_memory, TwoFieldStruct, __ENV__)
    end

    test "accept struct t type reflection string" do
      assert :ok ==
               ResolvePlanner.keep_struct_t_reflection(
                 :in_memory,
                 TwoFieldStruct,
                 "%TwoFieldStruct{...}"
               )
    end

    test "accept type names and module having precond functions handling the names" do
      assert :ok ==
               ResolvePlanner.plan_precond_checks(
                 :in_memory,
                 TwoFieldStruct,
                 title: "func_body",
                 duration: "func_body"
               )
    end

    test "accept struct fields for postponed integrity ensurance" do
      assert :ok ==
               ResolvePlanner.plan_struct_integrity_ensurance(
                 :in_memory,
                 TwoFieldStruct,
                 [title: "Hello", duration: 15],
                 "/module_path.ex",
                 9
               )
    end

    test "accept struct defaults for postponed ensurance" do
      assert :ok ==
               ResolvePlanner.plan_struct_defaults_ensurance(
                 :in_memory,
                 TwoFieldStruct,
                 [title: "Hello"],
                 "/module_path.ex",
                 2
               )
    end



    test "accept types to treat as any" do
      assert :ok ==
               ResolvePlanner.keep_global_remote_types_to_treat_as_any(
                 :in_memory,
                 %{Module => [:t]}
               )

      assert :ok ==
               ResolvePlanner.keep_remote_types_to_treat_as_any(
                 :in_memory,
                 TwoFieldStruct,
                 %{Module => [:name], Module1 => [:type1, :type2]}
               )
    end

    test "do nothing on flushing" do
      ResolvePlanner.keep_module_environment(:in_memory, TwoFieldStruct, __ENV__)

      assert :ok == ResolvePlanner.flush(:in_memory)
    end

    test "be able to clean plan in memory" do
      ResolvePlanner.plan_types_resolving(
        :in_memory,
        IncorrectDefault,
        :second,
        quote(do: Generator.a_str())
      )

      ResolvePlanner.plan_empty_struct(
        :in_memory,
        EmptyStruct
      )

      env = __ENV__
      ResolvePlanner.keep_module_environment(:in_memory, TwoFieldStruct, env)

      ResolvePlanner.keep_struct_t_reflection(:in_memory, TwoFieldStruct, "%TwoFieldStruct{...abc...}")

      ResolvePlanner.plan_struct_integrity_ensurance(
        :in_memory,
        TwoFieldStruct,
        [title: "Hello", duration: 15],
        "/module_path.ex",
        9
      )

      ResolvePlanner.plan_struct_defaults_ensurance(
        :in_memory,
        TwoFieldStruct,
        [title: "Hello"],
        "/module_path.ex",
        2
      )

      ResolvePlanner.keep_global_remote_types_to_treat_as_any(
        :in_memory,
        %{Module => [:t]}
      )

      ResolvePlanner.keep_remote_types_to_treat_as_any(
        :in_memory,
        TwoFieldStruct,
        %{Module => [:name], Module1 => [:type1, :type2]}
      )

      {:ok, plan, _preconds} = ResolvePlanner.get_plan_state(:in_memory)

      assert %{
               filed_types_to_resolve: %{
                 IncorrectDefault => %{second: quote(do: Generator.a_str())},
                 EmptyStruct => %{}
               },
               environments: %{TwoFieldStruct => env},
               t_reflections: %{TwoFieldStruct => "%TwoFieldStruct{...abc...}"},
               structs_to_ensure: [
                 {TwoFieldStruct, [title: "Hello", duration: 15], "/module_path.ex", 9}
               ],
               struct_defaults_to_ensure: [
                 {TwoFieldStruct, [title: "Hello"], "/module_path.ex", 2}
               ],
               remote_types_as_any_by_module: %{
                 :global => %{Module => [:t]},
                 TwoFieldStruct => %{Module => [:name], Module1 => [:type1, :type2]}
               }
             } == plan

      ResolvePlanner.clean_plan(:in_memory)

      {:ok, plan, _preconds} = ResolvePlanner.get_plan_state(:in_memory)

      assert %{
               filed_types_to_resolve: %{},
               environments: %{},
               t_reflections: %{},
               structs_to_ensure: [],
               struct_defaults_to_ensure: [],
               remote_types_as_any_by_module: %{}
             } == plan
    end

    test "plan precond checks" do
      assert :ok ==
               ResolvePlanner.plan_precond_checks(
                 :in_memory,
                 TwoFieldStruct,
                 title: "&String.length(&1) < 256",
                 duration: "fn val -> 5 < val and val < 15 end"
               )

      {:ok, _plan, preconds} = ResolvePlanner.get_plan_state(:in_memory)
      assert preconds == %{TwoFieldStruct => [title: "&String.length(&1) < 256", duration: "fn val -> 5 < val and val < 15 end"]}
    end

    test "overwrite existing struct field's type in plan (f.e. on fixing errors in type definitions and recompilation)" do
      ResolvePlanner.plan_types_resolving(
        :in_memory,
        TwoFieldStruct,
        :first,
        quote(do: integer)
      )

      atom_type = quote(do: atom)

      ResolvePlanner.plan_types_resolving(
        :in_memory,
        TwoFieldStruct,
        :first,
        atom_type
      )

      {:ok, plan, _preconds} = ResolvePlanner.get_plan_state(:in_memory)

      expected_field_types = %{TwoFieldStruct => %{first: atom_type}}
      assert %{filed_types_to_resolve: ^expected_field_types} = plan
    end

    test "register in memory modules types" do
      module = TwoFieldStruct

      assert ResolvePlanner.register_types(:in_memory, module, []) == :ok
      assert ResolvePlanner.get_types(:in_memory, module) == {:ok, []}

      type_list = [
        {:type, {:atom_hello, {:atom, 0, :hello}, []}},
        {:type, {:number_one, {:integer, 0, 1}, []}}
      ]

      assert ResolvePlanner.register_types(:in_memory, module, type_list) == :ok

      assert ResolvePlanner.get_types(:in_memory, module) == {:ok, type_list}
      assert ResolvePlanner.get_types(:in_memory, Atom) == {:error, :no_types_registered}
    end

    test "register in memory depending modules" do
      module = TwoFieldStruct

      assert ResolvePlanner.register_many_dependants(:in_memory, %{}) == :ok
      assert ResolvePlanner.get_dependants(:in_memory, module) == {:ok, []}

      dependencies = %{
        module => [Module]
      }

      assert ResolvePlanner.register_many_dependants(:in_memory, dependencies) == :ok
      assert ResolvePlanner.get_dependants(:in_memory, module) == {:ok, [Module]}
    end
  end

  describe "ResolvePlanner for sake of stop should" do
    setup do
      on_exit(fn ->
        ResolverTestHelper.stop_in_memory_planner()
      end)

      :ok
    end

    test "stop without flush" do
      {:ok, pid} = ResolvePlanner.start(:in_memory, :in_memory, [])
      ResolvePlanner.keep_module_environment(:in_memory, TwoFieldStruct, __ENV__)

      assert :ok == ResolvePlanner.stop(:in_memory)
      refute Process.alive?(pid)

      {:ok, pid} = ResolvePlanner.start(:in_memory, :in_memory, [])
      ResolvePlanner.keep_module_environment(:in_memory, TwoFieldStruct, __ENV__)

      assert :ok == ResolvePlanner.ensure_flushed_and_stopped(:in_memory)
      refute Process.alive?(pid)
    end

    test "Not stop if already stopped" do
      assert :ok == ResolvePlanner.stop(:in_memory)
    end
  end
end
