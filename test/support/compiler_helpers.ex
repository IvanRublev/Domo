defmodule CompilerHelpers do
  @moduledoc false

  def compile_with_elixir do
    command = Mix.Task.task_name(Mix.Tasks.Compile.Elixir)
    Mix.Task.rerun(command, [])
  end

  def setup_compiler_options do
    join_compiler_options(debug_info: true, ignore_module_conflict: true)
  end

  def reset_compiler_options do
    join_compiler_options(ignore_module_conflict: false)
  end

  def join_compiler_option(key, list) when is_list(list) do
    joined_list =
      key
      |> Code.get_compiler_option()
      |> List.wrap()
      |> Enum.concat(list)

    Code.put_compiler_option(key, joined_list)
  end

  defdelegate join_compiler_option(key, value), to: Code, as: :put_compiler_option

  def join_compiler_options(kw_list) when is_list(kw_list) do
    unless Keyword.keyword?(kw_list) do
      raise "Expected keyword list, got: #{inspect(kw_list)}"
    end

    Enum.each(kw_list, fn {key, value} ->
      join_compiler_option(key, value)
    end)
  end
end
