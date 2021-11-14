defmodule Domo.MixTasksCompileDomoTest do
  use Domo.FileCase, async: false
  use Placebo

  import ExUnit.CaptureIO

  alias Domo.TypeEnsurerFactory
  alias Domo.TypeEnsurerFactory.BatchEnsurer
  alias Domo.TypeEnsurerFactory.Cleaner
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.TypeEnsurerFactory.Resolver
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.MixProjectHelper
  alias Mix.Task.Compiler.Diagnostic
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

  @collectable_standard_lib_modules [
    Macro.Env,
    IO.Stream,
    GenEvent.Stream,
    Date.Range,
    Range,
    Regex,
    Task,
    URI,
    Version,
    Date,
    DateTime,
    NaiveDateTime,
    Time,
    File.Stat,
    File.Stream
  ]
  @collectable_optional_lib_modules [Decimal]
  @treat_as_any_optional_lib_modules [Ecto.Schema.Metadata]

  def env, do: __ENV__

  defp module_two_fields do
    {:module, _, _bytecode, _} =
      defmodule Module do
        use Domo

        defstruct first: :atom, second: 1.0
        @type t :: %__MODULE__{first: atom, second: float}
      end
  end

  defp module1_one_field do
    {:module, _, _bytecode, _} =
      defmodule Module1 do
        use Domo

        defstruct former: 0
        @type t :: %__MODULE__{former: integer}
      end
  end

  setup do
    MixProjectHelper.disable_raise_in_test_env()

    Code.compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)

    project = MixProjectHelper.global_stub()
    plan_file = DomoMixTask.manifest_path(project, :plan)
    preconds_file = DomoMixTask.manifest_path(project, :preconds)
    types_file = DomoMixTask.manifest_path(project, :types)
    deps_file = DomoMixTask.manifest_path(project, :deps)
    code_path = DomoMixTask.generated_code_path(project)

    # because server can run after compilation of the project
    ResolvePlanner.stop(plan_file)

    on_exit(fn ->
      ResolvePlanner.stop(plan_file)
    end)

    %{
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      code_path: code_path
    }
  end

  describe "Domo compiler task should" do
    setup do
      MixProjectHelper.disable_raise_in_test_env()

      allow BatchEnsurer.ensure_struct_defaults(any()), return: :ok
      allow BatchEnsurer.ensure_struct_integrity(any()), return: :ok
      allow Cleaner.rm!(any()), return: nil
      allow Cleaner.rmdir_if_exists!(any()), return: nil
      :ok
    end

    test "return {:noop, []} when no plan file exists that is domo is not used" do
      allow TypeEnsurerFactory.ensure_loaded?(any()), return: false
      allow TypeEnsurerFactory.has_type_ensurer?(any()), return: true
      assert {:noop, []} = DomoMixTask.run([])
    end

    test "start planner and plan t types of Elixir standard library struct having no TypeEnsurer modules", %{
      plan_file: plan_file,
      preconds_file: preconds_file
    } do
      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.plan_empty_struct(any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), return: false
      allow TypeEnsurerFactory.has_type_ensurer?(any()), exec: fn module -> module not in @collectable_standard_lib_modules end

      _ = DomoMixTask.run([])

      assert_called ResolvePlanner.ensure_started(plan_file, preconds_file)

      for module_name <- @collectable_standard_lib_modules do
        {_module, bytecode, _path} = :code.get_object_code(module_name)
        assert_called TypeEnsurerFactory.collect_types_for_domo_compiler(plan_file, is(&match?(%Macro.Env{module: ^module_name}, &1)), bytecode)
      end
    end

    test "start planner and plan t types of loaded optional library struct having no TypeEnsurer modules", %{
      plan_file: plan_file,
      preconds_file: preconds_file
    } do
      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.plan_empty_struct(any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), exec: fn module -> module in @collectable_optional_lib_modules end
      allow TypeEnsurerFactory.has_type_ensurer?(any()), exec: fn module -> module not in @collectable_optional_lib_modules end

      _ = DomoMixTask.run([])

      assert_called ResolvePlanner.ensure_started(plan_file, preconds_file)

      for module_name <- @collectable_optional_lib_modules do
        {_module, bytecode, _path} = :code.get_object_code(module_name)
        assert_called TypeEnsurerFactory.collect_types_for_domo_compiler(plan_file, is(&match?(%Macro.Env{module: ^module_name}, &1)), bytecode)
      end
    end

    test "only plan Elixir standard library structs missing TypeEnsurer module", %{plan_file: plan_file, preconds_file: preconds_file} do
      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.plan_empty_struct(any(), any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), return: false
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok

      allow TypeEnsurerFactory.has_type_ensurer?(any()),
        exec: fn
          Range -> true
          URI -> true
          module -> module not in @collectable_standard_lib_modules
        end

      _ = DomoMixTask.run([])

      assert_called ResolvePlanner.ensure_started(plan_file, preconds_file)

      for module_name <- [Range, URI] do
        refute_called(TypeEnsurerFactory.collect_types_for_domo_compiler(plan_file, is(&match?(%Macro.Env{module: ^module_name}, &1)), any()))
      end
    end

    test "plan some lib struct t() types to treat as any (like Ecto.Schema.Metadata.t)", %{
      plan_file: plan_file,
      preconds_file: preconds_file
    } do
      ResolverTestHelper.write_empty_plan(plan_file, preconds_file)
      on_exit(fn -> File.rm(plan_file) end)

      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.plan_empty_struct(any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_to_treat_as_any(any(), any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), exec: fn module -> module in @treat_as_any_optional_lib_modules end
      allow TypeEnsurerFactory.has_type_ensurer?(any()), return: false

      _ = DomoMixTask.run([])

      assert_called ResolvePlanner.ensure_started(plan_file, preconds_file)

      expected_types = Enum.map(@treat_as_any_optional_lib_modules, &{&1, [:t]})
      assert_called TypeEnsurerFactory.collect_types_to_treat_as_any(plan_file, nil, is(&(&1 == expected_types)), nil)
      assert_called ResolvePlanner.ensure_flushed_and_stopped(plan_file, any()), times(3)
    end

    test "only plan some lib struct to treat as any having loaded modules", %{
      plan_file: plan_file,
      preconds_file: preconds_file
    } do
      ResolverTestHelper.write_empty_plan(plan_file, preconds_file)
      on_exit(fn -> File.rm(plan_file) end)

      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.plan_empty_struct(any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_to_treat_as_any(any(), any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), return: false
      allow TypeEnsurerFactory.has_type_ensurer?(any()), return: true

      _ = DomoMixTask.run([])

      refute_called(TypeEnsurerFactory.collect_types_to_treat_as_any(any(), any(), any(), any()))
    end

    test "add some lib struct to treat as any only to existing plan" do
      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.plan_empty_struct(any(), any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), return: false
      allow TypeEnsurerFactory.collect_types_for_domo_compiler(any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.collect_types_to_treat_as_any(any(), any(), any(), any()), return: :ok
      allow TypeEnsurerFactory.has_type_ensurer?(any()), return: true

      _ = DomoMixTask.run([])

      refute_called(TypeEnsurerFactory.collect_types_to_treat_as_any(any(), any(), any(), any()))
    end

    test "Not start planner when no type ensurers missing for standard lib modules and no modules to treat as any are loaded", %{
      plan_file: plan_file,
      preconds_file: preconds_file
    } do
      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok
      allow TypeEnsurerFactory.ensure_loaded?(any()), return: false
      allow TypeEnsurerFactory.has_type_ensurer?(any()), return: true

      _ = DomoMixTask.run([])

      refute_called(ResolvePlanner.ensure_started(plan_file, preconds_file))
    end

    test "ensures that planner server flushed the plan and stopped", %{plan_file: plan_file} do
      allow ResolvePlanner.ensure_started(any(), any()), return: {:ok, self()}
      allow ResolvePlanner.keep_module_environment(any(), any(), any()), return: :ok
      allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), return: :ok
      allow ResolvePlanner.keep_global_remote_types_to_treat_as_any(any(), any()), return: :ok
      allow ResolvePlanner.stop(any()), return: :ok

      _ = DomoMixTask.run([])

      assert_called ResolvePlanner.ensure_flushed_and_stopped(plan_file, any())
    end

    test "resolve planned struct fields and struct dependencies for the project", %{
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      allow Resolver.resolve(any(), any(), any(), any(), any()),
        exec: fn _, _, _, _, _ ->
          File.write!(types_file, :erlang.term_to_binary(%{}))
        end

      on_exit(fn ->
        _ = File.rm(types_file)
      end)

      module_two_fields()
      module1_one_field()

      DomoMixTask.run([])

      assert_called Resolver.resolve(plan_file, preconds_file, types_file, deps_file, any())
    end

    test "return :error if resolve failed" do
      module_file = __ENV__.file

      allow Resolver.resolve(any(), any(), any(), any(), any()),
        seq: [
          {:error,
           [
             %Error{
               compiler_module: Resolver,
               file: module_file,
               struct_module: Module,
               message: :no_env_in_plan
             }
           ]},
          {:error,
           [
             %Error{
               compiler_module: Resolver,
               file: module_file,
               struct_module: Module,
               message: :keyword_list_should_has_atom_keys
             },
             %Error{
               compiler_module: Resolver,
               file: "nofile",
               struct_module: NonexistingModule,
               message: {:no_beam_file, NonexistingModule}
             }
           ]}
        ]

      module_two_fields()
      assert {:error, [diagnostic]} = DomoMixTask.run([])

      assert %Diagnostic{
               compiler_name: "Domo",
               file: ^module_file,
               message: "Domo.TypeEnsurerFactory.Resolver failed to resolve fields type of the Module struct due to :no_env_in_plan.",
               position: 1,
               severity: :error
             } = diagnostic

      module_two_fields()
      assert {:error, diagnostics} = DomoMixTask.run([])

      assert [
               %Diagnostic{
                 compiler_name: "Domo",
                 file: ^module_file,
                 message:
                   "Domo.TypeEnsurerFactory.Resolver failed to resolve fields type of the Module struct due to :keyword_list_should_has_atom_keys.",
                 position: 1,
                 severity: :error
               },
               %Diagnostic{
                 compiler_name: "Domo",
                 file: "nofile",
                 message:
                   "Domo.TypeEnsurerFactory.Resolver failed to resolve fields type of the NonexistingModule struct due to {:no_beam_file, NonexistingModule}.",
                 position: 1,
                 severity: :error
               }
             ] = diagnostics
    end

    test "write resolved struct filed types and struct dependant modules to manifest files", %{
      types_file: types_file,
      deps_file: deps_file
    } do
      module_two_fields()
      module1_one_field()

      refute File.exists?(types_file)
      refute File.exists?(deps_file)

      DomoMixTask.run([])

      assert File.exists?(types_file)
      assert File.exists?(deps_file)
    end

    test "generate the TypeEnsurer module source code from types manifest file", %{
      types_file: types_file,
      code_path: code_path
    } do
      allow Generator.generate(any(), any()), meck_options: [:passthrough], return: {:ok, []}

      module_two_fields()
      module1_one_field()

      DomoMixTask.run([])

      assert_called Generator.generate(types_file, code_path)
    end

    test "return error if module generation fails", %{code_path: code_path} do
      allow Generator.generate(any(), any()),
        return:
          {:error,
           %Error{
             compiler_module: Generator,
             file: code_path,
             struct_module: nil,
             message: :enomem
           }}

      module_two_fields()
      module1_one_field()

      assert {:error, [diagnostic]} = DomoMixTask.run([])

      assert %Diagnostic{
               compiler_name: "Domo",
               file: ^code_path,
               message: "Domo.TypeEnsurerFactory.Generator failed to generate TypeEnsurer module code due to :enomem.",
               position: 1,
               severity: :error
             } = diagnostic
    end

    test "compile the TypeEnsurer modules" do
      allow Generator.generate(any(), any()),
        meck_options: [:passthrough],
        exec: fn _, code_path ->
          File.mkdir_p(code_path)

          file_path = Path.join(code_path, "/module_type_ensurer.ex")

          File.write!(file_path, """
          defmodule Module.TypeEnsurer do
            def ensure_field_type, do: "Ok"
          end
          """)

          file_path1 = Path.join(code_path, "/module1_type_ensurer.ex")

          File.write!(file_path1, """
          defmodule Module1.TypeEnsurer do
            def ensure_field_type, do: "Ok 1"
          end
          """)

          {:ok, [file_path, file_path1]}
        end

      module_two_fields()

      DomoMixTask.run([])

      assert true == Code.ensure_loaded?(Module.TypeEnsurer)
      assert true == Code.ensure_loaded?(Module1.TypeEnsurer)
      assert "Ok" == apply(Module.TypeEnsurer, :ensure_field_type, [])
      assert "Ok 1" == apply(Module1.TypeEnsurer, :ensure_field_type, [])
    end

    test "return error if modules compilation fails", %{code_path: code_path} do
      file_path = Path.join(code_path, "/module_type_ensurer.ex")

      allow Generator.generate(any(), any()),
        meck_options: [:passthrough],
        exec: fn _, _code_path ->
          File.mkdir_p(code_path)

          File.write!(file_path, """
          defmodule Module.TypeEnsurer do
            malformed module
          end
          """)

          {:ok, [file_path]}
        end

      module_two_fields()

      capture_io(:stdio, fn ->
        send(self(), DomoMixTask.run([]))
      end)

      assert_receive {:error, [diagnostic]}

      assert %Diagnostic{
               compiler_name: "Domo",
               file: ^file_path,
               message: "Elixir compiler failed to compile a TypeEnsurer module" <> _,
               severity: :error
             } = diagnostic
    end

    test "returns {:ok, []} on successfull compilation" do
      module_two_fields()

      assert {:ok, []} = DomoMixTask.run([])
    end

    test "returns {:noop, []} when no modules were compiled" do
      allow Generator.generate(any(), any()), meck_options: [:passthrough], return: {:ok, []}

      module_two_fields()

      assert {:noop, []} = DomoMixTask.run([])
    end

    test "remove plan and types files on successfull compilation",
         %{
           plan_file: plan_file,
           types_file: types_file
         } do
      allow Cleaner.rm!(any()), return: nil
      allow Cleaner.rmdir_if_exists!(any()), return: nil

      module_two_fields()
      assert {:ok, []} = DomoMixTask.run([])

      assert_called Cleaner.rm!([plan_file, types_file])
    end

    test "remove previous type_ensurer modules source code giving existing plan file", %{code_path: code_path} do
      Placebo.unstub()

      allow Cleaner.rm!(any()), return: [:ok]

      me = self()

      allow Cleaner.rmdir_if_exists!(code_path),
        meck_options: [:passthrough],
        exec: fn _ ->
          send(me, :rmdir_if_exists!)
          :ok
        end

      allow Generator.generate(any(), any()),
        meck_options: [:passthrough],
        exec: fn _, _ ->
          send(me, :generate)
          {:ok, []}
        end

      module_two_fields()

      DomoMixTask.run([])

      assert self()
             |> Process.info(:messages)
             |> elem(1)
             |> Enum.filter(&(&1 in [:rmdir_if_exists!, :generate])) == [
               :rmdir_if_exists!,
               :generate
             ]
    end

    test "Not remove previous type_ensurer modules source code missing new plan file", %{code_path: code_path} do
      Placebo.unstub()

      allow Cleaner.rm!(any()), return: [:ok]

      me = self()

      allow Cleaner.rmdir_if_exists!(code_path),
        meck_options: [:passthrough],
        exec: fn _ ->
          send(me, :rmdir_if_exists!)
          :ok
        end

      DomoMixTask.run([])

      refute self()
             |> Process.info(:messages)
             |> elem(1)
             |> Enum.filter(&(&1 in [:rmdir_if_exists!, :generate])) == [:rmdir_if_exists!]
    end
  end

  describe "Domo compiler task for next run should" do
    test "recompile structs depending on structs with changed types with elixir", %{
      deps_file: deps_file,
      preconds_file: preconds_file
    } do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:ok, []}

      DomoMixTask.run([])

      assert_called DependencyResolver.maybe_recompile_depending_structs(deps_file, preconds_file, any())
    end

    test "continue normally giving Elixir not compiling anything for current app in umbrella project", %{
      deps_file: deps_file,
      preconds_file: preconds_file
    } do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:noop, []}

      assert DomoMixTask.run([])

      assert_called DependencyResolver.maybe_recompile_depending_structs(deps_file, preconds_file, any())
    end

    test "bypass underlying compilation error from DependencyResolver" do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()),
        return:
          {:error,
           [
             %Diagnostic{
               file: "/some_path",
               position: 1,
               message: "some syntax error",
               severity: :error,
               compiler_name: "Elixir"
             }
           ]}

      capture_io(:stdio, fn ->
        send(self(), DomoMixTask.run([]))
      end)

      assert_receive {:error, [diagnostic]}

      assert %Diagnostic{
               compiler_name: "Elixir",
               file: "/some_path",
               message: "some syntax error",
               severity: :error
             } = diagnostic
    end
  end

  test "Domo compiler task for verbose option should output debug info to console" do
    allow ResolvePlanner.ensure_flushed_and_stopped(any(), any()), meck_options: [:passthrough]

    module_two_fields()

    msg = capture_io(fn -> DomoMixTask.run(["--verbose"]) end)

    assert_called ResolvePlanner.ensure_flushed_and_stopped(any(), true)
    assert msg =~ ~r(Resolve types of Domo.MixTasksCompileDomoTest.Module)
    assert msg =~ ~r(Compiled .*/domo_mix_tasks_compile_domo_test_module_type_ensurer.ex)
  end

  describe "Domo compiler task for compilation errors should" do
    test "print error giving dependencies recompilation failure" do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()),
        return:
          {:error,
           [
             %Diagnostic{
               file: "/some_path",
               position: 1,
               message: "some syntax error",
               severity: :error,
               compiler_name: "Elixir"
             }
           ]}

      msg = capture_io(fn -> DomoMixTask.run([]) end)

      assert msg =~ "\n== Compilation error in file /some_path:1 ==\n** some syntax error\n"
    end

    test "print error giving a types resolve failure" do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:ok, []}

      allow Resolver.resolve(any(), any(), any(), any(), any()),
        return: {:error, %Error{compiler_module: Resolver, file: "/plan_path", message: :no_plan}}

      msg = capture_io(fn -> DomoMixTask.run([]) end)

      assert msg =~ "== Type ensurer compilation error in file /plan_path =="
      assert msg =~ ":no_plan"
    end

    test "print error giving a type ensurer generator failure" do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:ok, []}
      allow Resolver.resolve(any(), any(), any(), any(), any()), return: :ok

      allow Generator.generate(any(), any()),
        return:
          {:error,
           %Error{
             compiler_module: Generator,
             file: "/types_path",
             message: {:some_error, :failure}
           }}

      msg = capture_io(fn -> DomoMixTask.run([]) end)

      assert msg =~ "== Type ensurer compilation error in file /types_path =="
      assert msg =~ "{:some_error, :failure}"
    end

    test "print error giving a type ensurer compiltion failure" do
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:ok, []}
      allow Resolver.resolve(any(), any(), any(), any(), any()), return: :ok
      allow Generator.generate(any(), any()), return: {:ok, []}

      allow Generator.compile(any(), any()),
        return: {:error, [{"/ensurer_path", 1, "some syntax error"}], []}

      msg = capture_io(fn -> DomoMixTask.run([]) end)

      assert msg =~ "== Type ensurer compilation error in file /ensurer_path =="
      assert msg =~ "some syntax error"
    end
  end

  describe "Domo compiler task for compilation warnings should" do
    setup do
      MixProjectHelper.disable_raise_in_test_env()

      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()),
        return:
          {:ok,
           [
             %Diagnostic{
               file: "/some_path",
               position: 1,
               message: "a warning",
               severity: :warning,
               compiler_name: "Elixir"
             }
           ]}

      allow Resolver.resolve(any(), any(), any(), any(), any()), return: :ok
      allow Generator.generate(any(), any()), return: {:ok, []}

      allow Generator.compile(any(), any()),
        return: {:ok, [AModule], [{"/other_path", 2, "another warning"}]}

      allow BatchEnsurer.ensure_struct_defaults(any()), return: :ok
      allow BatchEnsurer.ensure_struct_integrity(any()), return: :ok

      allow Cleaner.rmdir_if_exists!(any()), return: :ok
      allow Cleaner.rm!(any()), return: :ok
      :ok
    end

    test "bypass warnings from deps and type_ensurer modules compilation" do
      capture_io(:stdio, fn ->
        send(self(), DomoMixTask.run([]))
      end)

      assert_receive {:ok, diagnostics}

      assert [
               %Diagnostic{
                 compiler_name: "Elixir",
                 file: "/some_path",
                 position: 1,
                 message: "a warning",
                 severity: :warning
               },
               %Diagnostic{
                 compiler_name: "Elixir",
                 file: "/other_path",
                 position: 2,
                 message: "another warning",
                 severity: :warning
               }
             ] = diagnostics
    end
  end

  describe "Domo compiler task clean/0 fucntion should" do
    test "remove plan, types, deps files and compiled code directory", %{
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      code_path: code_path
    } do
      File.touch!(plan_file)
      File.touch!(types_file)
      File.touch!(preconds_file)
      File.touch!(deps_file)
      File.mkdir_p!(code_path)
      File.touch!(Path.join([code_path, "file.ex"]))

      DomoMixTask.clean()

      refute File.exists?(plan_file)
      refute File.exists?(types_file)
      refute File.exists?(preconds_file)
      refute File.exists?(deps_file)
      refute File.exists?(code_path)
    end
  end
end
