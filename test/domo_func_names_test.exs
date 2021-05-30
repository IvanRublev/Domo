defmodule DomoFuncNamesTest do
  use Domo.FileCase, async: false
  use Placebo

  setup do
    Code.compiler_options(ignore_module_conflict: true)
    File.mkdir_p!(src_path())

    on_exit(fn ->
      Code.compiler_options(ignore_module_conflict: false)
    end)

    config = Mix.Project.config()
    config = Keyword.put(config, :elixirc_paths, [src_path() | config[:elixirc_paths]])
    allow Mix.Project.config(), meck_options: [:passthrough], return: config

    :ok
  end

  defp src_path do
    tmp_path("/src")
  end

  defp src_path(path) do
    Path.join([src_path(), path])
  end

  test "generates constructor with name set with name_of_new_function option globally or overriden with use Domo" do
    Application.put_env(:domo, :name_of_new_function, :custom_new)

    compile_titled_struct("TitleHolder")

    assert Kernel.function_exported?(TitleHolder, :custom_new, 1)
    assert Kernel.function_exported?(TitleHolder, :custom_new_ok, 1)

    compile_titled_struct("Titled", "name_of_new_function: :amazing_new")

    assert Kernel.function_exported?(Titled, :amazing_new, 1)
    assert Kernel.function_exported?(Titled, :amazing_new_ok, 1)
  after
    Application.delete_env(:domo, :name_of_new_function)
  end

  test "generates _ok function name dropping the last ! given with :name_of_new_function" do
    Application.put_env(:domo, :name_of_new_function, :custom_new!)

    compile_titled_struct("TitleHolder")

    assert Kernel.function_exported?(TitleHolder, :custom_new!, 1)
    assert Kernel.function_exported?(TitleHolder, :custom_new_ok, 1)

    compile_titled_struct("Titled", "name_of_new_function: :amazing_new!")

    assert Kernel.function_exported?(Titled, :amazing_new!, 1)
    assert Kernel.function_exported?(Titled, :amazing_new_ok, 1)
  after
    Application.delete_env(:domo, :name_of_new_function)
  end

  defp compile_titled_struct(module_name, use_arg \\ nil) do
    path = src_path("/titled_#{Enum.random(100..100_000)}.ex")

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

    compile_with_elixir()
  end

  defp compile_with_elixir do
    command = Mix.Utils.module_name_to_command("Mix.Tasks.Compile.Elixir", 2)
    Mix.Task.rerun(command, [])
  end
end
