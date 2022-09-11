defmodule BenchmarkEctoDomo.Util.TypesInspector do
  def inspect_types(env, bytecode) do
    {:ok, types} = Code.Typespec.fetch_types(bytecode)

    IO.puts("Types of #{env.module}:")

    Enum.map(types, fn {_kind, type} ->
      type_ast = Code.Typespec.type_to_quoted(type)

      type_ast
      |> Macro.to_string()
      |> IO.puts()
    end)
  end
end
