defmodule Domo.TypeEnsurerFactory.Generator do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Generator.MatchFunRegistry
  alias Domo.TypeEnsurerFactory.Generator.TypeSpec
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TypeEnsurerFactory.Precondition
  alias Kernel.ParallelCompiler

  def generate(types_path, ecto_assocs_path, output_folder, file_module \\ File) do
    with :ok <- make_output_folder(file_module, output_folder),
         {:ok, fields_by_module} <- decode_fields(file_module, types_path, {:read_types, :decode_types_file}),
         {:ok, ecto_assocs_by_module} <- decode_fields(file_module, ecto_assocs_path, {:read_ecto_assocs, :decode_ecto_assocs_file}) do
      case generate_many(fields_by_module, ecto_assocs_by_module, output_folder, file_module) do
        {:ok, paths} -> {:ok, Enum.reverse(paths)}
        error -> error
      end
    else
      {operation, {:error, error}, path} ->
        %Error{
          compiler_module: __MODULE__,
          file: path,
          struct_module: nil,
          message: {operation, error}
        }
    end
  end

  defp make_output_folder(file_module, output_folder) do
    case file_module.mkdir_p(output_folder) do
      :ok -> :ok
      {:error, _message} = error -> {:mkdir_output_folder, error, output_folder}
    end
  end

  defp decode_fields(file_module, path, {read_op, decode_op}) do
    case file_module.read(path) do
      {:ok, types_binary} ->
        try do
          {:ok, :erlang.binary_to_term(types_binary)}
        rescue
          _error -> {decode_op, {:error, :malformed_binary}, path}
        end

      {:error, _message} = error ->
        {read_op, error, path}
    end
  end

  defp generate_many(fields_by_module, ecto_assocs_by_module, output_folder, file_module) do
    Enum.reduce_while(fields_by_module, {:ok, []}, fn {parent_module, fields_spec}, acc ->
      ecto_assocs_fields = Map.get(ecto_assocs_by_module, parent_module, [])

      module_ast = generate_one(parent_module, fields_spec, ecto_assocs_fields)

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
    end)
  end

  defp module_filename(module_ast) do
    {:defmodule, _, [{:__aliases__, [alias: false], type_ensurer_items}, _]} = module_ast

    module_file =
      type_ensurer_items
      |> Enum.map_join(&to_string/1)
      |> Macro.underscore()

    "#{module_file}.ex"
  end

  # credo:disable-for-lines:118
  def generate_one(parent_module, fields_spec_t_precond, ecto_assoc_fields) do
    {:ok, pid} = MatchFunRegistry.start_link()

    {fields_spec, t_precond} = fields_spec_t_precond

    field_kinds =
      fields_spec
      |> collect_field_name_by_kind()
      |> Map.put(:ecto_assocs, ecto_assoc_fields)
      |> Macro.escape()

    t_precond_quoted = t_precondition_quoted(parent_module, t_precond)

    fields_spec
    |> Map.values()
    |> Enum.uniq()
    # TODO: this is not working and can be removed?
    |> Enum.reject(&any_specs?/1)
    |> Enum.concat()
    |> Enum.each(&MatchFunRegistry.register_match_spec_fun(pid, &1))

    ensure_type_field_functions = Enum.map(fields_spec, &ensure_type_function_quoted(parent_module, &1))

    match_spec_functions = MatchFunRegistry.list_functions_quoted(pid)

    MatchFunRegistry.stop(pid)

    {:__aliases__, [alias: false], parent_module_parts} = Alias.atom_to_alias(parent_module)
    type_ensurer_alias = {:__aliases__, [alias: false], parent_module_parts ++ [ModuleInspector.type_ensurer_atom()]}

    quote do
      defmodule unquote(type_ensurer_alias) do
        @moduledoc false

        def fields(kind), do: unquote(field_kinds) |> Map.get(kind)

        unquote(t_precond_quoted)

        unquote_splicing(ensure_type_field_functions)

        unquote_splicing(match_spec_functions)

        def do_match_spec({_spec_atom, _precond_atom}, value, spec_string, _opts) do
          message = Domo.ErrorBuilder.build_field_error(spec_string)
          {:error, value, [message]}
        end
      end
    end
  end

  def generate_invalid(parent_module) do
    {:__aliases__, [alias: false], parent_module_parts} = Alias.atom_to_alias(parent_module)
    type_ensurer_alias = {:__aliases__, [alias: false], parent_module_parts ++ [ModuleInspector.type_ensurer_atom()]}

    alias Domo.Raises

    quote do
      defmodule unquote(type_ensurer_alias) do
        @moduledoc false

        def fields(_kind), do: Raises.raise_invalid_type_ensurer(unquote(parent_module))

        def t_precondition(_value), do: Raises.raise_invalid_type_ensurer(unquote(parent_module))

        def ensure_field_type(_value, _opts), do: Raises.raise_invalid_type_ensurer(unquote(parent_module))
      end
    end
  end

  defp collect_field_name_by_kind(fields_spec) do
    {all, not_any, not_meta, not_any_not_meta, required_not_meta, required} =
      fields_spec
      |> Enum.sort_by(fn {field_name, _field_types} -> field_name end, :desc)
      |> Enum.reduce(
        {[], [], [], [], [], []},
        fn {field_name, field_types}, {all, not_any, not_meta, not_any_not_meta, required_not_meta, required} ->
          {any?, nil?} = any_nil_typed?(field_types)
          not_any_typed? = not any?
          not_nillable? = not nil?
          not_meta? = not meta_field?(field_name)

          {
            [field_name | all],
            if(not_any_typed?, do: [field_name | not_any], else: not_any),
            if(not_meta?, do: [field_name | not_meta], else: not_meta),
            if(not_any_typed? and not_meta?, do: [field_name | not_any_not_meta], else: not_any_not_meta),
            if(not_any_typed? and not_nillable? and not_meta?, do: [field_name | required_not_meta], else: required_not_meta),
            if(not_any_typed? and not_nillable?, do: [field_name | required], else: required)
          }
        end
      )

    %{
      typed_no_meta_no_any: not_any_not_meta,
      typed_no_meta_with_any: not_meta,
      typed_with_meta_no_any: not_any,
      typed_with_meta_with_any: all,
      required_no_meta: required_not_meta,
      required_with_meta: required
    }
  end

  defp any_nil_typed?(field_types) do
    Enum.reduce_while(field_types, {false, false}, fn field_type, {any?, nil?} ->
      updated_any? = any? or (match?({:term, _, _}, field_type) or match?({:any, _, _}, field_type))
      updated_nil? = nil? or is_nil(field_type)

      if updated_any? and updated_nil? do
        {:halt, {true, true}}
      else
        {:cont, {updated_any?, updated_nil?}}
      end
    end)
  end

  defp meta_field?(field_name) do
    field_string = Atom.to_string(field_name)
    underscore = "__"
    String.starts_with?(field_string, underscore) and String.ends_with?(field_string, underscore)
  end

  defp t_precondition_quoted(_struct_module, nil = _t_precond) do
    quote do
      def t_precondition(_value) do
        :ok
      end
    end
  end

  defp t_precondition_quoted(struct_module, t_precond) do
    struct_module_string = inspect(struct_module)
    value_var = quote(do: value)

    quote do
      def t_precondition(unquote(value_var)) do
        spec_string = "#{unquote(struct_module_string)}.t()"

        result = unquote(Precondition.ok_or_precond_call_quoted(t_precond, quote(do: spec_string), quote(do: value)))

        case result do
          :ok ->
            :ok

          {:error, value, [message]} ->
            {:error,
             {
               :type_mismatch,
               nil,
               nil,
               value,
               [spec_string],
               [message]
             }}
        end
      end
    end
  end

  # credo:disable-for-lines:46
  defp ensure_type_function_quoted(struct_module, {field, spec_precond_list}) do
    cond do
      any_specs?(spec_precond_list) ->
        quote do
          def ensure_field_type({unquote(field), _value}, _opts), do: :ok
        end

      match?([_spec], spec_precond_list) ->
        [spec_precond] = spec_precond_list
        {type_spec, precond} = TypeSpec.split_spec_precond(spec_precond)

        spec_atom = TypeSpec.to_atom(type_spec)
        precond_atom = if precond, do: Precondition.to_atom(precond)

        spec_string =
          spec_precond
          |> TypeSpec.filter_preconds()
          |> TypeSpec.spec_to_string()

        quote do
          def ensure_field_type({unquote(field), value}, opts) do
            case do_match_spec({unquote(spec_atom), unquote(precond_atom)}, value, unquote(spec_string), opts) do
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
          def ensure_field_type({unquote(field), value}, opts) do
            maybe_errors =
              Enum.reduce_while(unquote(spec_precond_atoms), [], fn {spec_atom, precond_atom, spec_string}, errors ->
                case do_match_spec({spec_atom, precond_atom}, value, spec_string, opts) do
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

  defp any_specs?(type_specs),
    do: Enum.any?(type_specs, &(&1 in [quote(do: any()), quote(do: term())]))

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
    IO.puts("Compiled #{file}")
  end
end
