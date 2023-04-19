defmodule Domo.MixTasksCompileDomoCompilerTest do
  use Domo.FileCase, async: false
  use Placebo

  import ExUnit.CaptureIO

  alias Domo.TypeEnsurerFactory.BatchEnsurer
  alias Domo.TypeEnsurerFactory.Cleaner
  alias Domo.TypeEnsurerFactory.DependencyResolver
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.ResolvePlanner
  alias Domo.TypeEnsurerFactory.Resolver
  alias Domo.CodeEvaluation
  alias Mix.Task.Compiler.Diagnostic
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask

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

  @moduletag empty_plan_on_disk?: false

  setup tags do
    ResolverTestHelper.disable_raise_in_test_env()
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true

    Code.compiler_options(ignore_module_conflict: true)

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
      ResolverTestHelper.enable_raise_in_test_env()

      Placebo.unstub()
      ResolverTestHelper.stop_project_palnner()
    end)

    project = MixProjectStubCorrect
    plan_file = DomoMixTask.manifest_path(project, :plan)
    preconds_file = DomoMixTask.manifest_path(project, :preconds)
    types_file = DomoMixTask.manifest_path(project, :types)
    deps_file = DomoMixTask.manifest_path(project, :deps)
    code_path = DomoMixTask.generated_code_path(project)
    ecto_assocs_file = DomoMixTask.manifest_path(project, :ecto_assocs)

    if tags.empty_plan_on_disk? do
      ResolverTestHelper.write_empty_plan(plan_file, preconds_file)
      on_exit(fn -> File.rm(plan_file) end)
    end

    %{
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      code_path: code_path,
      ecto_assocs_file: ecto_assocs_file
    }
  end

  def mock_deps(_context) do
    allow ResolvePlanner.ensure_started(any(), any(), any()), return: {:ok, self()}
    allow ResolvePlanner.ensure_flushed_and_stopped(any()), return: :ok
    allow ResolvePlanner.stop(any()), return: :ok
    allow ResolvePlanner.plan_types_resolving(any(), any(), any(), any()), return: :ok
    allow ResolvePlanner.keep_module_environment(any(), any(), any()), return: :ok
    allow ResolvePlanner.keep_global_remote_types_to_treat_as_any(any(), any()), return: :ok
    allow ResolvePlanner.plan_struct_defaults_ensurance(any(), any(), any(), any(), any()), return: :ok
    allow ResolvePlanner.types_treated_as_any(any()), return: {:ok, %{}}

    allow ModuleInspector.ensure_loaded?(any()), meck_options: [:passthrough], return: false
    allow ModuleInspector.has_type_ensurer?(any()), meck_options: [:passthrough], return: true

    allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:ok, []}

    allow BatchEnsurer.ensure_struct_defaults(any()), return: :ok
    allow BatchEnsurer.ensure_struct_integrity(any()), return: :ok

    allow Resolver.resolve(any(), any(), any(), any(), any(), any()), return: :ok

    allow Generator.generate(any(), any(), any()), return: {:ok, []}
    allow Generator.compile(any(), any()), return: {:ok, [], []}

    allow Cleaner.rm!(any()), return: nil
    allow Cleaner.rmdir_if_exists!(any()), return: nil

    :ok
  end

  describe "Domo compiler task should" do
    setup [:mock_deps]

    test "bypass error and stop plan collection giving error status from elixir" do
      DomoMixTask.start_plan_collection()

      error = {:error, [:diagnostic]}
      assert DomoMixTask.process_plan(error, []) == error
      assert_called ResolvePlanner.ensure_flushed_and_stopped(any())
    end

    test "pass on warnings from elixir" do
      DomoMixTask.start_plan_collection()

      warn = {:ok, [:diagnostic]}
      assert DomoMixTask.process_plan(warn, []) == warn
      assert_called ResolvePlanner.ensure_flushed_and_stopped(any())
    end

    test "set the plan collection flag to true on run and to false on process plan" do
      assert CodeEvaluation.in_plan_collection?() == false

      DomoMixTask.run([])

      assert CodeEvaluation.in_plan_collection?() == true

      DomoMixTask.process_plan({:ok, []}, [])

      assert CodeEvaluation.in_plan_collection?() == false
    end

    test "bypass status from previous compiler when no plan file exists (that is domo is not used)" do
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    end

    @tag empty_plan_on_disk?: true
    test "plan struct t() types to treat as any (like Ecto.Schema.Metadata.t)", %{plan_file: plan_file} do
      allow ModuleInspector.ensure_loaded?(any()), meck_options: [:passthrough], return: true
      allow ModuleInspector.has_type_ensurer?(any()), meck_options: [:passthrough], return: false

      _ = DomoMixTask.process_plan({:ok, []}, [])

      expected_types = @treat_as_any_optional_lib_modules |> Enum.map(&{&1, [:t]}) |> Enum.into(%{})
      assert_called ResolvePlanner.keep_global_remote_types_to_treat_as_any(plan_file, expected_types)
    end

    @tag empty_plan_on_disk?: true
    test "Not plan struct types to treat as any having their modules unloadable" do
      DomoMixTask.process_plan({:ok, []}, [])

      refute_called(ResolvePlanner.keep_global_remote_types_to_treat_as_any(any(), any()))
    end

    test "Not plan struct types to treat as any having no plan file", %{plan_file: plan_file} do
      refute File.exists?(plan_file)

      _ = DomoMixTask.process_plan({:ok, []}, [])

      refute_called(ResolvePlanner.keep_global_remote_types_to_treat_as_any(any(), any()))
    end

    test "ensures that planner server flushed the plan and stopped", %{plan_file: plan_file} do
      _ = DomoMixTask.process_plan({:ok, []}, [])

      assert_called ResolvePlanner.ensure_flushed_and_stopped(plan_file)
    end

    test "resolve planned struct fields and struct dependencies for the project", %{
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      DomoMixTask.start_plan_collection()

      module_two_fields()
      module1_one_field()

      DomoMixTask.process_plan({:ok, []}, [])

      assert_called Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, any())
    end

    test "return :error if resolve failed" do
      module_file = __ENV__.file

      :meck.unload(Resolver)

      allow Resolver.resolve(any(), any(), any(), any(), any(), any()),
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

      DomoMixTask.start_plan_collection()
      module_two_fields()
      assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])

      assert %Diagnostic{
               compiler_name: "Domo",
               file: ^module_file,
               message: "Domo.TypeEnsurerFactory.Resolver failed to resolve fields type of the Module struct due to :no_env_in_plan.",
               position: 1,
               severity: :error
             } = diagnostic

      DomoMixTask.start_plan_collection()
      module_two_fields()
      assert {:error, diagnostics} = DomoMixTask.process_plan({:ok, []}, [])

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

    test "generate the TypeEnsurer module source code from types manifest file", %{
      types_file: types_file,
      ecto_assocs_file: ecto_assocs_file,
      code_path: code_path
    } do
      DomoMixTask.start_plan_collection()
      module_two_fields()
      module1_one_field()
      DomoMixTask.process_plan({:ok, []}, [])

      assert_called Generator.generate(types_file, ecto_assocs_file, code_path)
    end

    test "return error if module generation fails", %{code_path: code_path} do
      :meck.unload(Generator)

      allow Generator.generate(any(), any(), any()),
        return:
          {:error,
           %Error{
             compiler_module: Generator,
             file: code_path,
             struct_module: nil,
             message: :enomem
           }}

      DomoMixTask.start_plan_collection()

      module_two_fields()
      module1_one_field()

      assert {:error, [diagnostic]} = DomoMixTask.process_plan({:ok, []}, [])

      assert %Diagnostic{
               compiler_name: "Domo",
               file: ^code_path,
               message: "Domo.TypeEnsurerFactory.Generator failed to generate TypeEnsurer module code due to :enomem.",
               position: 1,
               severity: :error
             } = diagnostic
    end

    test "compile the TypeEnsurer modules" do
      :meck.unload(Generator)

      allow Generator.generate(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn _, _, code_path ->
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

      DomoMixTask.start_plan_collection()
      module_two_fields()
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])

      assert true == Code.ensure_loaded?(Module.TypeEnsurer)
      assert true == Code.ensure_loaded?(Module1.TypeEnsurer)
      assert "Ok" == apply(Module.TypeEnsurer, :ensure_field_type, [])
      assert "Ok 1" == apply(Module1.TypeEnsurer, :ensure_field_type, [])
    end

    test "return error if modules compilation fails", %{code_path: code_path} do
      file_path = Path.join(code_path, "/module_type_ensurer.ex")

      :meck.unload(Generator)

      allow Generator.generate(any(), any(), any()),
        meck_options: [:passthrough],
        exec: fn _, _, _code_path ->
          File.mkdir_p(code_path)

          File.write!(file_path, """
          defmodule Module.TypeEnsurer do
            malformed module
          end
          """)

          {:ok, [file_path]}
        end

      DomoMixTask.start_plan_collection()

      module_two_fields()

      capture_io(:stdio, fn ->
        send(self(), DomoMixTask.process_plan({:ok, []}, []))
      end)

      assert_receive {:error, [diagnostic]}

      assert %Diagnostic{
               compiler_name: "Domo",
               file: ^file_path,
               message: "Elixir compiler failed to compile a TypeEnsurer module" <> _,
               severity: :error
             } = diagnostic
    end

    @tag empty_plan_on_disk?: true
    test "returns status from previous compiler when no modules were compiled" do
      DomoMixTask.start_plan_collection()
      assert {:ok, []} = DomoMixTask.process_plan({:ok, []}, [])
    end

    test "ensures struct defaults and struct integrity" do
      DomoMixTask.process_plan({:ok, []}, [])
      assert_called BatchEnsurer.ensure_struct_defaults(any()), return: :ok
      assert_called BatchEnsurer.ensure_struct_integrity(any()), return: :ok
    end

    test "remove plan and types files on successful compilation", %{plan_file: plan_file, types_file: types_file} do
      DomoMixTask.start_plan_collection()
      module_two_fields()
      DomoMixTask.process_plan({:ok, []}, [])

      assert_called Cleaner.rm!([plan_file, types_file])
    end

    @tag empty_plan_on_disk?: true
    test "remove previous type_ensurer modules source code giving existing plan file", %{code_path: code_path} do
      DomoMixTask.process_plan({:ok, []}, [])
      assert_called Cleaner.rmdir_if_exists!(code_path)
    end

    test "Not remove previous type_ensurer modules source code missing new plan file", %{code_path: code_path} do
      DomoMixTask.process_plan({:ok, []}, [])
      refute_called(Cleaner.rmdir_if_exists!(code_path))
    end
  end

  describe "Domo compiler task for next run should" do
    setup [:mock_deps]

    test "recompile structs depending on structs with changed types with elixir", %{
      deps_file: deps_file,
      preconds_file: preconds_file
    } do
      DomoMixTask.process_plan({:ok, []}, [])

      assert_called ResolvePlanner.ensure_started(any(), any(), any())
      assert_called DependencyResolver.maybe_recompile_depending_structs(deps_file, preconds_file, any())
      assert_called ResolvePlanner.ensure_flushed_and_stopped(any())
    end

    test "continue normally giving Elixir not compiling anything for current app in umbrella project", %{
      deps_file: deps_file,
      preconds_file: preconds_file
    } do
      :meck.unload(DependencyResolver)
      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()), return: {:noop, []}

      DomoMixTask.process_plan({:ok, []}, [])

      assert_called ResolvePlanner.ensure_started(any(), any(), any())
      assert_called DependencyResolver.maybe_recompile_depending_structs(deps_file, preconds_file, any())
      assert_called ResolvePlanner.stop(any())
    end

    test "bypass underlying compilation error from DependencyResolver" do
      :meck.unload(DependencyResolver)

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
        send(self(), DomoMixTask.process_plan({:ok, []}, []))
      end)

      assert_called ResolvePlanner.ensure_started(any(), any(), any())
      assert_receive {:error, [diagnostic]}

      assert %Diagnostic{
               compiler_name: "Elixir",
               file: "/some_path",
               message: "some syntax error",
               severity: :error
             } = diagnostic

      assert_called ResolvePlanner.stop(any())
    end

    test "bypass underlying deps or preconds read error from DependencyResolver" do
      :meck.unload(DependencyResolver)

      allow DependencyResolver.maybe_recompile_depending_structs(any(), any(), any()),
        return: %Error{
          compiler_module: DependencyResolver,
          file: "/deps_path_here",
          struct_module: nil,
          message: "deps or preconds read error"
        }

      capture_io(:stdio, fn ->
        send(self(), DomoMixTask.process_plan({:ok, []}, []))
      end)

      assert_called ResolvePlanner.ensure_started(any(), any(), any())
      assert_receive {:error, [diagnostic]}

      assert %Diagnostic{
               compiler_name: "Domo",
               file: "/deps_path_here",
               message: "Domo.TypeEnsurerFactory.DependencyResolver failed to recompile depending structs due to \"deps or preconds read error\".",
               severity: :error
             } = diagnostic

      assert_called ResolvePlanner.stop(any())
    end
  end

  test "Domo compiler task for verbose option should output debug info to console" do
    msg =
      capture_io(fn ->
        DomoMixTask.start_plan_collection(["--verbose"])

        module_two_fields()

        DomoMixTask.process_plan({:ok, []}, ["--verbose"])
      end)

    assert msg =~ ~r(Domo resolve planner started)
    assert msg =~ ~r(Resolve types of Domo.MixTasksCompileDomoCompilerTest.Module)
    assert msg =~ ~r(Compiled .*/domo_mix_tasks_compile_domo_compiler_test_module_type_ensurer.ex)
  end

  describe "Domo compiler task for compilation errors should" do
    setup [:mock_deps]

    test "print error giving dependencies recompilation failure" do
      :meck.unload(DependencyResolver)

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

      msg = capture_io(fn -> DomoMixTask.process_plan({:ok, []}, []) end)

      assert msg =~ "\n== Compilation error in file /some_path:1 ==\n** some syntax error\n"
    end

    test "print error giving a types resolve failure" do
      :meck.unload(Resolver)

      allow Resolver.resolve(any(), any(), any(), any(), any(), any()),
        return: {:error, %Error{compiler_module: Resolver, file: "/plan_path", message: :no_plan}}

      msg = capture_io(fn -> DomoMixTask.process_plan({:ok, []}, []) end)

      assert msg =~ "== Type ensurer compilation error in file /plan_path =="
      assert msg =~ ":no_plan"
    end

    test "print error giving a type ensurer generator failure" do
      :meck.unload(Generator)

      allow Generator.generate(any(), any(), any()),
        return:
          {:error,
           %Error{
             compiler_module: Generator,
             file: "/types_path",
             message: {:some_error, :failure}
           }}

      msg = capture_io(fn -> DomoMixTask.process_plan({:ok, []}, []) end)

      assert msg =~ "== Type ensurer compilation error in file /types_path =="
      assert msg =~ "{:some_error, :failure}"
    end

    test "print error giving a type ensurer compiltion failure" do
      :meck.unload(Generator)
      allow Generator.generate(any(), any(), any()), return: {:ok, []}

      allow Generator.compile(any(), any()),
        return: {:error, [{"/ensurer_path", 1, "some syntax error"}], []}

      msg = capture_io(fn -> DomoMixTask.process_plan({:ok, []}, []) end)

      assert msg =~ "== Type ensurer compilation error in file /ensurer_path =="
      assert msg =~ "some syntax error"
    end
  end

  describe "Domo compiler task for compilation warnings should" do
    setup [:mock_deps]

    test "bypass warnings from deps and type_ensurer modules compilation" do
      :meck.unload(DependencyResolver)

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

      :meck.unload(Generator)
      allow Generator.generate(any(), any(), any()), return: {:ok, []}
      allow Generator.compile(any(), any()), return: {:ok, [AModule], [{"/other_path", 2, "another warning"}]}

      capture_io(:stdio, fn ->
        send(self(), DomoMixTask.process_plan({:ok, []}, []))
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

  describe "Domo compiler task clean/0 function should" do
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
