defmodule Domo.Raises do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.MixProjectHelper

  @add_domo_compiler_message """
  Domo compiler is expected to do a second-pass of the compilation \
  to resolve remote types that are in the project's BEAM files \
  and generate TypeEnsurer modules.
  Please, ensure that :domo_compiler is included after the :elixir \
  in the compilers list in the project/0 function in mix.exs file. \
  Like [compilers: Mix.compilers() ++ [:domo_compiler], ...]\
  """

  @precond_arguments """
  precond/1 expects [key: value] argument where the key is a type name \
  atom and the value is an anonymous boolean function with one argument \
  returning wheither the precondition is fullfiled \
  for a value of the given type.\
  """

  def raise_struct_should_be_passed(module_should, instead_of: module_instead) do
    raise ArgumentError, """
    the #{inspect(module_should)} structure should be passed as \
    the first argument value instead of #{inspect(module_instead)}.\
    """
  end

  def raise_or_warn_values_should_have_expected_types(opts, module, errors) do
    error_points =
      errors
      |> Enum.map(&(" * " <> cast_to_string(&1)))
      |> Enum.join("\n")

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
        description: "use Domo should be called in a module scope only. To have tagged tuple functions try use Domo.TaggedTuple instead."
      )
    end
  end

  def raise_absence_of_domo_compiler!(project_configuration, opts, caller_env) do
    project_stub =
      MixProjectHelper.opts_stub(opts, caller_env) ||
        MixProjectHelper.global_stub(project_configuration)

    configuration = if project_stub, do: project_stub.config(), else: project_configuration

    compilers = Keyword.get(configuration, :compilers, [])
    elixir_idx = Enum.find_index(compilers, &(:elixir == &1))
    domo_idx = Enum.find_index(compilers, &(:domo_compiler == &1))

    unless not is_nil(elixir_idx) and not is_nil(domo_idx) and domo_idx > elixir_idx do
      raise CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: @add_domo_compiler_message
    end
  end

  def maybe_raise_add_domo_compiler(module) do
    unless Code.ensure_loaded?(Module.concat(module, TypeEnsurer)) do
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

  def raise_not_in_a_struct_module!(caller_env) do
    # In elixir v1.12.0 :struct is renamed to :__struct__ https://github.com/elixir-lang/elixir/pull/10354
    unless Module.has_attribute?(caller_env.module, :__struct__) or Module.has_attribute?(caller_env.module, :struct) do
      raise CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: """
        use Domo should be called from within the module \
        defining a struct.
        """
    end
  end

  def raise_no_type_t_defined!(caller_env) do
    unless has_type_t?(caller_env) do
      raise(CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: """
        Type t() should be defined for the struct #{inspect(caller_env.module)}, \
        that enables Domo to generate type ensurer module for the struct's data.\
        """
      )
    end
  end

  defp has_type_t?(caller_env) do
    caller_env.module
    |> Module.get_attribute(:type)
    |> Enum.find_value(fn {:type, {:"::", _, spec}, _} ->
      with [{:t, _, _}, t_type] <- spec,
           {:%, _, [module, {:%{}, _, _}]} <- t_type do
        case module do
          {:__MODULE__, _, _} -> true
          {:__aliases__, _, _} = an_alias -> Alias.alias_to_atom(an_alias) == caller_env.module
          module when is_atom(module) -> module == caller_env.module
          _typo_after_percentage -> false
        end
      else
        _ -> false
      end
    end)
  end
end
