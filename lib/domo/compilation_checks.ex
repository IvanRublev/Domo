defmodule Domo.CompilationChecks do
  @moduledoc """
  Module to validate tags and structs after compilation of a given module.
  """

  @doc """
  Emits warnings about missing aliases for tag modules. After emmiting
  all warnings raises the CompileError with count of missing tags.

  If all referenced tags are defined does nothing.
  """
  @spec warn_and_raise_undefined_tags(map, any) :: nil
  def warn_and_raise_undefined_tags(env, _bytecode) do
    env.module
    |> Module.get_attribute(:domo_tags)
    |> Enum.uniq()
    |> Enum.reverse()
    |> Enum.filter(&not_tag_module?/1)
    |> Enum.map(&warn_non_tag_module/1)
    |> Enum.count()
    |> raise_on_undefined_tags_if_needed(env)
  end

  defp not_tag_module?({atom, _}) when is_atom(atom),
    do:
      not match?({:module, _}, Code.ensure_compiled(atom)) or
        not Kernel.function_exported?(atom, :__tag__?, 0)

  defp warn_non_tag_module({atom, stacktrace_entry}) do
    name = Atom.to_string(atom) |> String.split(".") |> List.last()

    IO.warn(
      "#{name} is not a tag defined with deftag/2. Have you missed an alias Some.Path.#{name}?",
      [stacktrace_entry]
    )
  end

  defp raise_on_undefined_tags_if_needed(0, _env), do: nil

  defp raise_on_undefined_tags_if_needed(count, env) do
    msg =
      cond do
        count > 1 -> "#{count} tags were not defined with deftag\/2. See warnings."
        true -> "A tag was not defined with deftag\/2. See warning."
      end

    v =
      Keyword.fetch(
        Module.get_attribute(env.module, :domo_opts),
        :undefined_tag_error_as_warning
      )

    case v do
      {:ok, true} ->
        IO.warn(msg)

      _ ->
        raise(CompileError,
          file: env.file,
          line: env.line,
          description: msg
        )
    end
  end
end
