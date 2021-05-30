defmodule Domo.TypeEnsurerFactory.Alias do
  @moduledoc false

  @spec atom_to_alias(atom()) :: tuple()
  def atom_to_alias(term) when is_atom(term) do
    {:__aliases__, [alias: false],
     term
     |> Atom.to_string()
     |> String.split(".")
     |> Enum.map(&String.to_atom/1)
     |> Enum.filter(&(&1 != Elixir))}
  end

  def atom_to_alias(term), do: term

  @spec alias_to_atom(tuple) :: atom()
  def alias_to_atom({:__aliases__, options, module_parts}) do
    case Keyword.get(options, :alias) do
      false -> Module.concat(module_parts)
      full_name -> full_name
    end
  end

  def alias_to_atom(term), do: term

  @spec string_by_concat(any, atom) :: String.t()
  def string_by_concat(atom_or_alias, atom) do
    atom_or_alias
    |> alias_to_atom()
    |> Module.concat(atom)
    |> Module.split()
    |> Enum.reject(&(&1 == "Elixir"))
    |> Enum.join(".")
  end
end
