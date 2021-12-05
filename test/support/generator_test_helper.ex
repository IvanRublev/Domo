defmodule GeneratorTestHelper do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Generator

  def load_type_ensurer_module(field_spec) do
    field_spec
    |> type_ensurer_quoted_with_no_preconds()
    |> Code.eval_quoted()
  end

  def load_type_ensurer_module_with_no_preconds(field_spec) do
    field_spec
    |> ResolverTestHelper.add_empty_precond_to_spec()
    |> type_ensurer_quoted_with_no_preconds()
    |> Code.eval_quoted()
  end

  def type_ensurer_quoted_with_no_preconds(field_spec) do
    Generator.generate_one(Elixir, field_spec)
  end
end
