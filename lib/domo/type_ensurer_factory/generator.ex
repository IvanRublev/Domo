defmodule Domo.TypeEnsurerFactory.Generator do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Error
  alias __MODULE__.MatchFunRegistry
  alias __MODULE__.TypeSpec
  alias Kernel.ParallelCompiler

  def generate(types_path, output_folder, file_module \\ File) do
    with {:mkdir_output_folder, :ok} <-
           {:mkdir_output_folder, file_module.mkdir_p(output_folder)},
         {:read_types, {:ok, types_binary}} <-
           {:read_types, file_module.read(types_path)},
         {:decode_types_file, {:ok, fields_by_modules}} <-
           {:decode_types_file, binary_to_term(types_binary)} do
      write_type_ensurer_modules(fields_by_modules, output_folder, file_module)
    else
      {operation, {:error, error}} ->
        %Error{
          compiler_module: __MODULE__,
          file: types_path,
          struct_module: nil,
          message: {operation, error}
        }
    end
  end

  defp binary_to_term(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      _error -> {:error, :malformed_binary}
    end
  end

  defp write_type_ensurer_modules(fields_by_modules, output_folder, file_module) do
    case Enum.reduce_while(
           fields_by_modules,
           {:ok, []},
           &write_module_while(output_folder, &1, &2, file_module)
         ) do
      {:ok, paths} -> {:ok, Enum.reverse(paths)}
      error -> error
    end
  end

  defp write_module_while(output_folder, item, acc, file_module) do
    {parent_module, fields_spec} = item

    module_ast = do_type_ensurer_module(parent_module, fields_spec)

    module_path = Path.join(output_folder, module_filename(module_ast))
    module_binary = Macro.to_string(module_ast) |> Code.format_string!()

    case file_module.write(module_path, module_binary) do
      :ok ->
        {:ok, paths} = acc
        {:cont, {:ok, [module_path | paths]}}

      {:error, error} ->
        {:halt,
         %Error{
           compiler_module: __MODULE__,
           file: module_path,
           struct_module: parent_module,
           message: {:write_type_ensurer_module, error}
         }}
    end
  end

  defp module_filename(module_ast) do
    {:defmodule, _, [{:__aliases__, [alias: false], type_ensurer_items}, _]} = module_ast

    module_file =
      type_ensurer_items
      |> Enum.map(&to_string/1)
      |> Enum.join()
      |> Macro.underscore()

    "#{module_file}.ex"
  end

  @spec do_type_ensurer_module(module(), map()) :: tuple()
  def do_type_ensurer_module(parent_module, fields_spec) do
    {:ok, pid} = MatchFunRegistry.start_link()

    fields_spec = TypeSpec.generalize_specs_for_ensurable_structs(fields_spec)

    fields_spec
    |> Map.values()
    |> Enum.reject(&any_spec?/1)
    |> Enum.concat()
    |> Enum.each(&MatchFunRegistry.register_match_spec_fun(pid, &1))

    ensure_type_field_functions = Enum.map(fields_spec, &ensure_type_function_quoted/1)

    match_spec_functions = MatchFunRegistry.list_functions_quoted(pid)

    MatchFunRegistry.stop(pid)

    {:__aliases__, [alias: false], parent_module_parts} = Alias.atom_to_alias(parent_module)
    type_ensurer_alias = {:__aliases__, [alias: false], parent_module_parts ++ [:TypeEnsurer]}

    quote do
      defmodule unquote(type_ensurer_alias) do
        @moduledoc false

        unquote_splicing(ensure_type_field_functions)

        unquote_splicing(match_spec_functions)

        def do_match_spec(type_spec_atom, value) do
          message = {"Expected the value matching the %{type} type.", type: type_spec_atom}
          {:error, value, [message]}
        end

        def pretty_error_by_key({:error, {:type_mismatch, field, _, _, _}} = error) do
          {field, pretty_error(error)}
        end

        def pretty_error({
              :error,
              {:type_mismatch, field, value, expected_types, error_templates}
            }) do
          or_type_spec = Enum.join(expected_types, " | ")

          general_error = "Expected the value matching the #{or_type_spec} type."

          underlying_errors =
            error_templates
            |> List.flatten()
            |> Enum.map(fn {template, args} -> interpolate_error_template(template, args) end)
            |> Enum.join("\n")

          expected_spec_string =
            if general_error != underlying_errors do
              general_error <> "\nUnderlying errors:\n" <> underlying_errors
            else
              general_error
            end

          "Invalid value #{inspect(value)} for field #{inspect(field)}. " <> expected_spec_string
        end

        defp interpolate_error_template(template, args) do
          Enum.reduce(args, template, fn {key, value}, template ->
            string = if is_nil(value), do: "nil", else: to_string(value)
            String.replace(template, "%{#{key}}", string)
          end)
        end
      end
    end
  end

  # credo:disable-for-lines:46
  defp ensure_type_function_quoted({field, specs}) do
    cond do
      any_spec?(specs) ->
        quote do
          def ensure_type!({unquote(field), value}), do: :ok
        end

      match?([_spec], specs) ->
        [spec] = specs
        spec_atom = TypeSpec.to_atom(spec)
        spec_string = TypeSpec.spec_to_string(spec)

        quote do
          def ensure_type!({unquote(field), value}) do
            case do_match_spec(unquote(spec_atom), value) do
              :ok ->
                :ok

              {:error, _value, message} ->
                {:error, {:type_mismatch, unquote(field), value, unquote([spec_string]), message}}
            end
          end
        end

      true ->
        spec_atoms = Enum.map(specs, &TypeSpec.to_atom(&1))
        spec_strings = Enum.map(specs, &TypeSpec.spec_to_string(&1))

        quote do
          def ensure_type!({unquote(field), value}) do
            maybe_errors =
              Enum.reduce_while(unquote(spec_atoms), [], fn spec_atom, errors ->
                case do_match_spec(spec_atom, value) do
                  {:error, _value, message} -> {:cont, [message | errors]}
                  _ -> {:halt, nil}
                end
              end)

            if is_nil(maybe_errors) do
              :ok
            else
              {:error,
               {:type_mismatch, unquote(field), value, unquote(spec_strings), maybe_errors}}
            end
          end
        end
    end
  end

  defp any_spec?(type_spec),
    do: Enum.any?(type_spec, &(&1 in [quote(do: any()), quote(do: term())]))

  def compile(paths, verbose? \\ false) do
    project = Mix.Project.config()
    dest = Mix.Project.compile_path(project)
    opts = opts(verbose?)

    ParallelCompiler.compile_to_path(
      paths,
      dest,
      opts
    )
  end

  defp opts(false = _verbose?) do
    cwd = File.cwd!()
    threshold_sec = 10

    [
      long_compilation_threshold: threshold_sec,
      each_long_compilation: &each_long_compilation(&1, cwd, threshold_sec)
    ]
  end

  defp opts(true = _verbose?) do
    cwd = File.cwd!()

    false
    |> opts()
    |> Keyword.merge(each_file: &each_file(&1, cwd))
  end

  defp each_long_compilation(file, cwd, threshold_sec) do
    file = Path.relative_to(file, cwd)
    IO.warn("Compilation of #{file} takes longer then #{threshold_sec}sec.", [])
  end

  defp each_file(file, cwd) do
    file = Path.relative_to(file, cwd)
    IO.write("Compiled #{file}\n")
  end
end
