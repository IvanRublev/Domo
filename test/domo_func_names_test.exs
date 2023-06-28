defmodule DomoFuncNamesTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias Domo.MixProject

  setup do
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true
    :ok
  end

  test "generates constructor with name set with gen_constructor_name option globally or overridden with use Domo" do
    Application.put_env(:domo, :gen_constructor_name, :custom_new)

    DomoMixTask.start_plan_collection()
    compile_titled_struct("TitleHolder")

    assert Kernel.function_exported?(TitleHolder, :custom_new, 1)
    assert Kernel.function_exported?(TitleHolder, :custom_new!, 1)

    compile_titled_struct("Titled", "gen_constructor_name: :amazing_new")

    assert Kernel.function_exported?(Titled, :amazing_new, 1)
    assert Kernel.function_exported?(Titled, :amazing_new!, 1)
  after
    Application.delete_env(:domo, :gen_constructor_name)
    DomoMixTask.stop_plan_collection()
  end

  defp compile_titled_struct(module_name, use_arg \\ nil) do
    path = MixProject.out_of_project_tmp_path("/titled_#{Enum.random(100..100_000)}.ex")

    use_domo =
      ["use Domo", use_arg]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    File.write!(path, """
    defmodule #{module_name} do
      #{use_domo}

      @enforce_keys [:title]
      defstruct [:title]

      @type t :: %__MODULE__{title: String.t()}
    end
    """)

    CompilerHelpers.compile_with_elixir()
  end
end
