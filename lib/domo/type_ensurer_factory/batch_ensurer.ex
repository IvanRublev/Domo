defmodule Domo.TypeEnsurerFactory.BatchEnsurer do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Error

  def ensure_struct_integrity(plan_path) do
    with {:ok, structs_to_ensure} <- read_plan(plan_path),
         :ok <- do_ensure_structs_integrity(structs_to_ensure) do
      :ok
    else
      {:module_error_by_key, module_error_by_key} ->
        {:error, build_file_line_message(module_error_by_key)}

      {:error, errors} ->
        {:error, wrap_error(errors)}
    end
  end

  defp build_file_line_message(module_error_by_key) do
    {module, file, line, error_by_key} = module_error_by_key
    {_keys, errors} = Enum.unzip(error_by_key)

    {:__aliases__, [alias: false], parts} = Alias.atom_to_alias(module)

    module =
      parts
      |> Enum.map(&to_string/1)
      |> Enum.join(".")

    message = Enum.join(["Failed to build #{module} struct." | errors], "\n")
    {file, line, message}
  end

  defp wrap_error(errors) do
    errors
    |> List.wrap()
    |> Enum.map(&%Error{&1 | compiler_module: __MODULE__})
  end

  @spec read_plan(String.t()) :: {:ok, {map, list}} | {:error, map}
  defp read_plan(plan_path) do
    case File.read(plan_path) do
      {:ok, binary} ->
        map = :erlang.binary_to_term(binary)
        {:ok, map.structs_to_ensure}

      _err ->
        {:error, %Error{file: plan_path, message: :no_plan}}
    end
  end

  defp do_ensure_structs_integrity([{module, fields, file, line} | tail]) do
    case apply(module, :new_ok, [fields]) do
      {:ok, _struct} ->
        do_ensure_structs_integrity(tail)

      {:error, error_by_key} ->
        # Have to wait 1 second to touch files with later epoch time
        # and make elixir compiler to percept them as stale files.
        Process.sleep(1000)

        File.touch!(file)
        Enum.each(tail, fn {_module, _fields, file, _line} -> File.touch!(file) end)
        {:module_error_by_key, {module, file, line, error_by_key}}
    end
  end

  defp do_ensure_structs_integrity([]) do
    :ok
  end
end
