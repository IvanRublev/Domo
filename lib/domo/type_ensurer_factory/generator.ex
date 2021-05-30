defmodule Domo.TypeEnsurerFactory.Generator do
  @moduledoc false

  alias Domo.Precondition
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Error
  alias __MODULE__.MatchFunRegistry
  alias __MODULE__.TypeSpec
  alias Kernel.ParallelCompiler

  def generate(types_path, output_folder, file_module \\ File) do
    with :ok <- make_output_folder(file_module, output_folder),
         {:ok, types_binary} <- read_types(file_module, types_path),
         {:ok, fields_by_modules} <- decode_types(types_binary) do
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

  defp make_output_folder(file_module, output_folder) do
    case file_module.mkdir_p(output_folder) do
      :ok -> :ok
      {:error, _message} = error -> {:mkdir_output_folder, error}
    end
  end

  defp read_types(file_module, types_path) do
    case file_module.read(types_path) do
      {:ok, _types_binary} = ok -> ok
      {:error, _message} = error -> {:read_types, error}
    end
  end

  defp decode_types(types_binary) do
    try do
      {:ok, :erlang.binary_to_term(types_binary)}
    rescue
      _error -> {:decode_types_file, {:error, :malformed_binary}}
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

  # credo:disable-for-lines:118
  @spec do_type_ensurer_module(module(), map()) :: tuple()
  def do_type_ensurer_module(parent_module, fields_spec_t_precond) do
    {:ok, pid} = MatchFunRegistry.start_link()

    {fields_spec, t_precond} = TypeSpec.generalize_specs_for_ensurable_structs(fields_spec_t_precond)

    t_precond_quoted = t_precondition_quoted(parent_module, t_precond)

    fields_spec
    |> Map.values()
    |> Enum.reject(&any_spec?/1)
    |> Enum.concat()
    |> Enum.each(&MatchFunRegistry.register_match_spec_fun(pid, &1))

    ensure_type_field_functions = Enum.map(fields_spec, &ensure_type_function_quoted(parent_module, &1))

    match_spec_functions = MatchFunRegistry.list_functions_quoted(pid)

    MatchFunRegistry.stop(pid)

    {:__aliases__, [alias: false], parent_module_parts} = Alias.atom_to_alias(parent_module)
    type_ensurer_alias = {:__aliases__, [alias: false], parent_module_parts ++ [:TypeEnsurer]}

    quote do
      defmodule unquote(type_ensurer_alias) do
        @moduledoc false

        unquote(t_precond_quoted)

        unquote_splicing(ensure_type_field_functions)

        unquote_splicing(match_spec_functions)

        def do_match_spec({_spec_atom, _precond_atom}, value, spec_string) do
          message = build_error(spec_string, nil)
          {:error, value, [message]}
        end

        defp build_error(spec_string, [precond_description: _description, precond_type: _type_string] = opts) do
          {template, keywords} = build_error(spec_string, nil)

          template =
            template <>
              " And a true value from the precondition" <>
              " function \"%{precond_description}\" defined for %{precond_type} type."

          keywords = Keyword.merge(keywords, opts)

          {template, keywords}
        end

        defp build_error(spec_string, nil) do
          {"Expected the value matching the %{type} type.", type: spec_string}
        end

        def pretty_error_by_key({:error, {_, _, field, _, _, _}} = error) do
          {field || :t, pretty_error(error)}
        end

        def pretty_error({:error, {:type_mismatch, struct_module, field, value, expected_types, error_templates}}) do
          field_string = if field, do: "for field #{inspect(field)} of %#{inspect(struct_module)}{}"

          value_description =
            [
              "Invalid value",
              inspect(value),
              field_string
            ]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" ")

          {underlying_error_types, count} =
            error_templates
            |> List.flatten()
            |> Enum.reduce({[], 0}, fn {_msg, list}, {types, count} -> {[list[:type] | types], count + length(list)} end)

          only_primitive_or_values = Enum.reverse(underlying_error_types) == expected_types and count == length(expected_types)

          or_type_spec = Enum.join(expected_types, " | ")
          general_or_error = "Expected the value matching the #{or_type_spec} type."

          error_templates = List.flatten(error_templates)
          {general_error_template, general_error_args} = hd(error_templates)
          rest_underlying_errors = List.delete_at(error_templates, 0)
          general_error = interpolate_error_template(general_error_template, general_error_args)

          {general_error_string, underlying_errors} =
            if String.starts_with?(general_error, general_or_error) do
              {general_error, rest_underlying_errors}
            else
              {general_or_error, error_templates}
            end

          underlying_error_strings =
            underlying_errors
            |> Enum.map(fn {template, args} -> "   - " <> interpolate_error_template(template, args) end)
            |> Enum.join("\n")

          underlying_error_strings =
            unless underlying_error_strings == "" or only_primitive_or_values == true do
              "\nUnderlying errors:\n" <> underlying_error_strings
            end

          "#{value_description}. #{general_error_string}#{underlying_error_strings}"
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

  defp t_precondition_quoted(_struct_module, nil) do
    quote do
      def t_precondition(_value) do
        :ok
      end
    end
  end

  defp t_precondition_quoted(struct_module, t_precond) do
    struct_module_string = inspect(struct_module)

    quote do
      def t_precondition(value) do
        if unquote(Precondition.validation_call_quoted(t_precond, quote(do: value))) do
          :ok
        else
          type_spec = "#{unquote(struct_module_string)}.t()"

          message =
            build_error(
              type_spec,
              precond_description: unquote(t_precond.description),
              precond_type: unquote(Precondition.type_string(t_precond))
            )

          {:error,
           {
             :type_mismatch,
             nil,
             nil,
             value,
             [type_spec],
             [message]
           }}
        end
      end
    end
  end

  # credo:disable-for-lines:46
  defp ensure_type_function_quoted(struct_module, {field, spec_precond_list}) do
    cond do
      any_spec?(spec_precond_list) ->
        quote do
          def ensure_field_type({unquote(field), value}), do: :ok
        end

      match?([_spec], spec_precond_list) ->
        [spec_precond] = spec_precond_list
        {spec, precond} = TypeSpec.split_spec_precond(spec_precond)

        spec_atom = TypeSpec.to_atom(spec)
        precond_atom = if precond, do: Precondition.to_atom(precond)

        spec_string =
          spec_precond
          |> TypeSpec.filter_preconds()
          |> TypeSpec.spec_to_string()

        quote do
          def ensure_field_type({unquote(field), value}) do
            case do_match_spec({unquote(spec_atom), unquote(precond_atom)}, value, unquote(spec_string)) do
              :ok ->
                :ok

              {:error, _value, message} ->
                {:error, {:type_mismatch, unquote(struct_module), unquote(field), value, unquote([spec_string]), message}}
            end
          end
        end

      true ->
        {specs, preconds} =
          spec_precond_list
          |> Enum.map(&TypeSpec.split_spec_precond(&1))
          |> Enum.unzip()

        spec_atoms = Enum.map(specs, &TypeSpec.to_atom(&1))
        precond_atoms = Enum.map(preconds, &if(&1, do: Precondition.to_atom(&1)))
        spec_strings = Enum.map(specs, &({&1, nil} |> TypeSpec.filter_preconds() |> TypeSpec.spec_to_string()))

        spec_precond_atoms =
          [spec_atoms, precond_atoms, spec_strings]
          |> Enum.zip()
          |> Macro.escape()

        spec_strings = Macro.escape(spec_strings)

        quote do
          def ensure_field_type({unquote(field), value}) do
            maybe_errors =
              Enum.reduce_while(unquote(spec_precond_atoms), [], fn {spec_atom, precond_atom, spec_string}, errors ->
                case do_match_spec({spec_atom, precond_atom}, value, spec_string) do
                  :ok ->
                    {:halt, nil}

                  {:error, _value, message} ->
                    {:cont, [message | errors]}
                end
              end)

            if is_nil(maybe_errors) do
              :ok
            else
              {:error, {:type_mismatch, unquote(struct_module), unquote(field), value, unquote(spec_strings), Enum.reverse(maybe_errors)}}
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
