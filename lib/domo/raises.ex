defmodule Domo.Raises do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ModuleInspector

  @add_domo_compiler_message """
  Domo compiler is expected to do a second-pass compilation \
  to resolve remote types that are in the project's BEAM files \
  and generate TypeEnsurer modules.
  More details are in https://hexdocs.pm/domo/Domo.html#module-setup
  To queue the second-pass, please, add :domo_compiler before the :elixir \
  in mix.exs file like the following:

    def project do
      [
        compilers: [:domo_compiler] ++ Mix.compilers(),
        ...
      ]
    end
  """

  @precond_arguments """
  precond/1 expects [key: value] argument where the key is a type name \
  atom and the value is an anonymous boolean function with one argument \
  returning whether the precondition is fulfilled \
  for a value of the given type.\
  """

  @correct_format_remote_types_as_any_message """
  :remote_types_as_any option value must be of the following shape \
  [{:module, :type}, {:module, [:type1, :type2]}].\
  """

  def raise_struct_should_be_passed(module_should, instead_of: module_instead) do
    raise ArgumentError, """
    the #{inspect(module_should)} structure should be passed as \
    the first argument value instead of #{inspect(module_instead)}.\
    """
  end

  def raise_or_warn_values_should_have_expected_types(opts, module, errors) do
    error_points = Enum.map_join(errors, "\n", &(" * " <> cast_to_string(&1)))

    raise_or_warn(opts, ArgumentError, """
    the following values should have types defined for fields of the #{inspect(module)} struct:
    #{error_points}\
    """)
  end

  defp cast_to_string(value) when is_binary(value), do: value
  defp cast_to_string(value), do: inspect(value)

  def raise_or_warn_struct_precondition_should_be_true(opts, t_error) do
    raise_or_warn(opts, ArgumentError, t_error)
  end

  def raise_or_warn(opts, error, message) do
    global_as_warning? = Application.get_env(:domo, :unexpected_type_error_as_warning, false)
    warn? = Keyword.get(opts, :unexpected_type_error_as_warning, global_as_warning?)

    if warn? do
      IO.warn(message)
    else
      raise error, message
    end
  end

  def raise_use_domo_out_of_module!(caller_env) do
    unless ModuleInspector.module_context?(caller_env) do
      raise(CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: "use Domo should be called in a module scope only."
      )
    end
  end

  def maybe_raise_absence_of_domo_compiler!(configuration, caller_env) do
    compilers = Keyword.get(configuration, :compilers, [])
    domo_idx = Enum.find_index(compilers, &(:domo_compiler == &1))
    elixir_idx = Enum.find_index(compilers, &(:elixir == &1))

    unless not is_nil(elixir_idx) and not is_nil(domo_idx) and domo_idx < elixir_idx do
      raise CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: @add_domo_compiler_message
    end
  end

  def raise_only_interactive(module, caller_env) do
    raise CompileError,
      file: caller_env.file,
      line: caller_env.line,
      description: "#{inspect(module)} should be used only in interactive elixir."
  end

  def raise_incorrect_remote_types_as_any_format!([_ | _] = list) do
    unless Enum.all?(list, &valid_type_as_any_option_item?/1) do
      raise ArgumentError, @correct_format_remote_types_as_any_message
    end
  end

  def raise_incorrect_remote_types_as_any_format!(_) do
    raise ArgumentError, @correct_format_remote_types_as_any_message
  end

  defp valid_type_as_any_option_item?(item) do
    case item do
      {module, type} when is_atom(module) and is_atom(type) -> true
      {module, [_ | _] = types_list} when is_atom(module) -> Enum.all?(types_list, &is_atom/1)
      {{:__aliases__, _, _}, type} when is_atom(type) -> true
      {{:__aliases__, _, _}, [_ | _] = types_list} -> Enum.all?(types_list, &is_atom/1)
      _ -> false
    end
  end

  def maybe_raise_add_domo_compiler(module) do
    unless ModuleInspector.has_type_ensurer?(module) do
      raise @add_domo_compiler_message
    end
  end

  def raise_precond_arguments do
    raise ArgumentError, @precond_arguments
  end

  def raise_nonexistent_type_for_precond(type_name) do
    raise ArgumentError, """
    precond/1 is called with undefined #{inspect(type_name)} type name. \
    The name of a type defined with @type attribute is expected.\
    """
  end

  def raise_compilation_error({file, line, message}) do
    raise CompileError,
      file: file,
      line: line,
      description: message
  end

  def raise_cant_find_type_in_memory({:no_types_registered, type_string}) do
    raise """
    Can't resolve #{type_string} type. Please, define the module first \
    or use Domo.InteractiveTypesRegistration in it to inform Domo about the types.\
    """
  end

  def maybe_raise_incorrect_placement!(caller_env) do
    module = caller_env.module
    file = caller_env.file
    line = caller_env.line

    types = Module.get_attribute(module, :type)
    opaques = Module.get_attribute(module, :opaque)

    quoted_types =
      [types, opaques]
      |> Enum.concat()
      |> Enum.map(fn {_kind, quoted_type, _meta} -> quoted_type end)

    in_struct? = ModuleInspector.struct_module?(module)

    if in_struct? do
      t_type = ModuleInspector.find_t_type(quoted_types)

      unless struct_type?(t_type, module) do
        raise(CompileError,
          file: file,
          line: line,
          description: """
          Type @type or @opaque t :: %__MODULE__{...} should be defined in the \
          #{inspect(caller_env.module)} struct's module, \
          that enables Domo to generate type ensurer module for the struct's data.\
          """
        )
      end
    else
      has_parametrized_types? = Enum.any?(quoted_types, &match?({:"::", _, [_, [_ | _]]}, &1))

      unless has_parametrized_types? do
        raise CompileError,
          line: line,
          description: "use Domo should be called from within the module defining a struct."
      end
    end
  end

  defp struct_type?({:ok, type_quoted, _}, expected_module) do
    case type_quoted do
      {:%, _, [module, {:%{}, _, _}]} ->
        case module do
          {:__MODULE__, _, _} -> true
          {:__aliases__, _, _} = an_alias -> Alias.alias_to_atom(an_alias) == expected_module
          module when is_atom(module) -> module == expected_module
          _typo_after_percentage -> false
        end

      _ ->
        false
    end
  end

  defp struct_type?(_type_quoted, _expected_module) do
    false
  end

  def raise_no_schema_module do
    raise """
    Can't find schema module because changeset contains map data. \
    Please, pass schema module with validate_type(changeset, schema_module) call.
    """
  end

  def raise_no_type_ensurer_for_schema_module(module) do
    module_string = Alias.atom_to_string(module)
    raise "No type ensurer for the schema module found. Please, use Domo in #{module_string} schema module."
  end

  def raise_no_ecto_module() do
    raise "No Ecto.Changeset module is compiled. Please, add https://hex.pm/packages/ecto package to the dependencies section in the mix.exs file of the project."
  end

  def raise_not_defined_fields(extra_fields, module) do
    raise "No fields #{inspect(extra_fields)} are defined in the #{inspect(module)}.t() type."
  end

  def raise_cant_build_in_test_environment(module) do
    raise """
    Domo can't build TypeEnsurer module in the test environment for #{inspect(module)}. \
    Please, put structs using Domo into compilation directories specific to your test environment \
    and put paths to them in your mix.exs:

    def project do
      ...
      elixirc_paths: elixirc_paths(Mix.env())
      ...
    end

    defp elixirc_paths(:test), do: ["lib", "test/support"]
    defp elixirc_paths(_), do: ["lib"]
    """
  end

  def warn_invalidated_type_ensurers(module, dependencies) do
    deps_string = Enum.map_join(dependencies, ",", &inspect/1)

    IO.warn("""
    TypeEnsurer modules are invalidated. Please, redefine the following modules depending on #{inspect(module)} \
    to make their types ensurable again: #{deps_string}\
    """)
  end

  def raise_invalid_type_ensurer(module) do
    raise """
    TypeEnsurer module is invalid. Please, redefine #{inspect(module)} \
    to make constructor, validation, and reflection functions to work again.\
    """
  end

  def raise_no_elixir_compiler_was_run do
    raise CompileError,
      file: "domo_phoenix_hot_reload",
      line: 0,
      description: """
      :elixir compiler wasn't run. Please, check if :domo_phoenix_hot_reload \
      is placed after :elixir in the compilers list in the mix.exs file and \
      in reloadable_compilers list in the configuration file.\
      """
  end
end
