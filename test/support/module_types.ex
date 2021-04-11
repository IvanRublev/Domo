defmodule ModuleTypes do
  @moduledoc false

  def types(bytecode) do
    bytecode
    |> Code.Typespec.fetch_types()
    |> elem(1)
    |> Enum.sort()
  end

  def specs(bytecode) do
    bytecode
    |> Code.Typespec.fetch_specs()
    |> elem(1)
    |> Enum.sort()
  end

  def specs_to_string(specs) do
    specs
    |> Enum.map(fn {{func, _args}, [spec]} -> Code.Typespec.spec_to_quoted(func, spec) end)
    |> Macro.to_string()
  end
end
