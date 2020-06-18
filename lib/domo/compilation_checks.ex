defmodule Domo.CompilationChecks do
  @moduledoc false

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

    domo_options = Module.get_attribute(env.module, :domo_options)

    warning_option =
      case Keyword.fetch(domo_options, :undefined_tag_error_as_warning) do
        {:ok, value} -> value
        _ -> Application.get_env(:domo, :undefined_tag_error_as_warning, false)
      end

    case warning_option do
      true ->
        IO.warn(msg)

      _ ->
        IO.inspect raise(CompileError,
          file: env.file,
          line: env.line,
          description: msg
        )
    end
  end
end
