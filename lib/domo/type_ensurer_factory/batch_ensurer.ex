defmodule Domo.TypeEnsurerFactory.BatchEnsurer do
  @moduledoc false

  alias Domo.ErrorBuilder
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Error

  def ensure_struct_integrity(plan_path) do
    with {:ok, plan_map} <- read_plan(plan_path),
         {:ok, structs_to_ensure} <- read_field(plan_map, plan_path, :structs_to_ensure),
         :ok <- do_ensure_structs_integrity(structs_to_ensure) do
      :ok
    else
      {:module_error_by_key, module_error_by_key} ->
        {:error, build_file_line_message(module_error_by_key)}

      {:error, errors} ->
        {:error, wrap_error(errors)}
    end
  end

  defp read_plan(plan_path) do
    case File.read(plan_path) do
      {:ok, binary} ->
        {:ok, :erlang.binary_to_term(binary)}

      _err ->
        {:error, %Error{file: plan_path, message: :no_plan}}
    end
  end

  defp read_field(plan, plan_path, field) do
    case Map.get(plan, field) do
      nil -> {:error, %Error{file: plan_path, message: {:no_field_in_plan, field}}}
      value -> {:ok, value}
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

  defp do_ensure_structs_integrity([{module, fields, file, line} | tail]) do
    case apply(module, :new_ok, [fields]) do
      {:ok, _struct} ->
        do_ensure_structs_integrity(tail)

      {:error, error_by_key} ->
        touch_files([file | Enum.map(tail, fn {_module, _fields, file, _line} -> file end)])
        {:module_error_by_key, {module, file, line, error_by_key}}
    end
  end

  defp do_ensure_structs_integrity([]) do
    :ok
  end

  defp touch_files(files) do
    # Have to wait 1 second to touch files with later epoch time
    # and make elixir compiler to percept them as stale files.
    Process.sleep(1000)
    Enum.map(files, &File.touch!(&1))
  end

  def ensure_struct_defaults(plan_path) do
    with {:ok, plan_map} <- read_plan(plan_path),
         {:ok, defaults_to_ensure} <- read_field(plan_map, plan_path, :struct_defaults_to_ensure),
         :ok <- do_ensure_struct_defaults(defaults_to_ensure) do
      :ok
    else
      {:module_error, module_error} ->
        {:error, build_defaults_error_message(module_error)}

      {:error, errors} ->
        {:error, wrap_error(errors)}
    end
  end

  defp do_ensure_struct_defaults([{module, fields, file, line} | tail]) do
    with :ok <- validate_fields(module, fields),
         :ok <- validate_struct_value(module, fields) do
      do_ensure_struct_defaults(tail)
    else
      {:error, error} ->
        touch_files([file | Enum.map(tail, fn {_module, _fields, file, _line} -> file end)])
        {:module_error, {module, file, line, error}}
    end
  end

  defp do_ensure_struct_defaults([]) do
    :ok
  end

  defp validate_fields(module, fields) do
    type_ensurer = Module.concat(module, TypeEnsurer)

    required_fields = apply(type_ensurer, :fields, [:typed_no_meta_no_any])

    Enum.reduce_while(required_fields, :ok, fn key, ok ->
      key_value = {key, fields[key]}

      case apply(type_ensurer, :ensure_field_type, [key_value]) do
        {:error, _} = error -> {:halt, {:error, ErrorBuilder.pretty_error(error)}}
        _ -> {:cont, ok}
      end
    end)
  end

  defp validate_struct_value(module, fields) do
    type_ensurer = Module.concat(module, TypeEnsurer)
    value = struct(module, fields)

    case apply(type_ensurer, :t_precondition, [value]) do
      :ok -> :ok
      {:error, _} = error -> {:error, ErrorBuilder.pretty_error(error)}
    end
  end

  defp build_defaults_error_message(module_error) do
    {module, file, line, error} = module_error

    module_string = Alias.atom_to_string(module)

    message = """
    A default value given via defstruct/1 in #{module_string} module mismatches the type.
    #{inspect(error)}
    """

    {file, line, message}
  end
end
