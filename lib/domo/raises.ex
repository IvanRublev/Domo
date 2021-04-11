defmodule Domo.Raises do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.MixProjectHelper

  def raise_use_domo_out_of_module!(caller_env) do
    unless ModuleInspector.module_context?(caller_env) do
      raise(CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description:
          "use Domo should be called in a module scope only. To have tagged tuple functions try use Domo.TaggedTuple instead."
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
    domo_idx = Enum.find_index(compilers, &(:domo == &1))

    unless not is_nil(elixir_idx) and not is_nil(domo_idx) and domo_idx > elixir_idx do
      raise CompileError,
        file: caller_env.file,
        line: caller_env.line,
        description: """
        Domo should be included after the :elixir in the compilers list \
        in the project's configuration mix.exs file because it launches \
        the second-pass of the compilation to resolve remote types \
        that are in project BEAM files.
        The mix.exs should have project/0 function returning a list \
        with the following key compilers: Mix.compilers() ++ [:domo] \
        where the :domo location is after the :elixir compiler.\
        """
    end
  end

  def raise_not_in_a_struct_module!(caller_env) do
    unless Module.has_attribute?(caller_env.module, :struct) do
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
           {:%, _, [{_, _, _} = module, {:%{}, _, _}]} <- t_type do
        case module do
          {:__MODULE__, _, _} -> true
          {:__aliases__, _, _} = an_alias -> Alias.alias_to_atom(an_alias) == caller_env.module
        end
      else
        _ -> false
      end
    end)
  end
end
