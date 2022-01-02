defmodule Domo.InteractiveTypesRegistration do
  @moduledoc """
  This module registers types of the module that can be referenced from
  struct type specs.

  Should be used in interactive shell only. When Domo is launched
  with `mix compile` command, it reads module types from Beam files directly.

  Example:

      iex(1)> defmodule SharedTypes do
         ...>   use Domo.InteractiveTypesRegistration
         ...>
         ...>   @type id :: String.t() | nil
         ...> end

  Now the `SharedTypes.id` can be referenced from a struct interactively:

      iex(2)> defmodule MyStruct do
         ...>   use Domo
         ...>   defstruct [:id]
         ...>   @type t :: %__MODULE__{id: SharedTypes.id()}
         ...> end
  """

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory
  alias Domo.Raises

  defmacro __using__(_opts) do
    if CodeEvaluation.in_mix_compile?() do
      Raises.raise_only_interactive(__MODULE__, __CALLER__)
    end

    # We consider to be in interactive mode
    opts = [verbose?: Application.get_env(:domo, :verbose_in_iex, false)]
    TypeEnsurerFactory.start_resolve_planner(:in_memory, :in_memory, opts)

    quote do
      @after_compile {Domo.InteractiveTypesRegistration, :register_in_memory_types}
    end
  end

  def register_in_memory_types(env, bytecode) do
    TypeEnsurerFactory.register_in_memory_types(env.module, bytecode)

    {:ok, dependants} = TypeEnsurerFactory.get_dependants(:in_memory, env.module)

    unless dependants == [] do
      TypeEnsurerFactory.invalidate_type_ensurers(dependants)
      Raises.warn_invalidated_type_ensurers(env.module, dependants)
    end
  end
end
