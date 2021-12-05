defmodule Domo.TypeEnsurerFactory.ModuleInspector do
  @moduledoc false

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory.ResolvePlanner

  @type_ensurer_atom :TypeEnsurer

  defdelegate ensure_loaded?(module), to: Code

  def module_context?(env) do
    not is_nil(env.module) and is_nil(env.function)
  end

  def type_ensurer_atom, do: @type_ensurer_atom

  def type_ensurer(module), do: Module.concat(module, @type_ensurer_atom)

  def beam_types_hash(module) do
    case beam_types(module) do
      {:ok, type_list} -> type_list |> :erlang.term_to_binary() |> :erlang.md5()
      _error -> nil
    end
  end

  def has_type_ensurer?(module) do
    type_ensurer = type_ensurer(module)
    Code.ensure_loaded?(type_ensurer)
  end

  def beam_types(module) do
    case beam_types_from_file(module) do
      {:ok, _types} = ok ->
        ok

      {:error, {:no_beam_file, _module}} = error ->
        if CodeEvaluation.in_mix_compile?(__ENV__) do
          error
        else
          ResolvePlanner.get_types(:in_memory, module)
        end
    end
  end

  defp beam_types_from_file(module) do
    case fetch_direct_types(module) do
      {:ok, _type_list} = ok -> ok
      :error -> {:error, {:no_beam_file, module}}
    end
  end

  def fetch_direct_types(module_or_bytecode) do
    case Code.Typespec.fetch_types(module_or_bytecode) do
      {:ok, type_list} -> {:ok, Enum.reject(type_list, &parametrized_type?/1)}
      :error -> :error
    end
  end

  defp parametrized_type?({kind, {_name, _definition, [_ | _] = _arg_list}}) when kind in [:type, :opaque] do
    true
  end

  defp parametrized_type?(_type) do
    false
  end

  def find_type_quoted(name, type_list, dereferenced_types \\ []) do
    notfound = {:error, {:type_not_found, name}}
    notsupported = {:error, {:parametrized_type_not_supported, name}}

    case Enum.find_value(type_list, notfound, &having_name(name, &1)) do
      {:ok, :user_type, _target_name, {_, {:user_type, _, _, [_ | _] = _args}, _}} ->
        notsupported

      {:ok, :user_type, target_name, _type} ->
        find_type_quoted(target_name, type_list, [target_name | dereferenced_types])

      {:ok, :remote_type, _target_name, type} ->
        quoted_type =
          type
          |> Code.Typespec.type_to_quoted()
          |> target_type_quoted()
          |> clean_remote_meta()

        {:ok, quoted_type, Enum.reverse(dereferenced_types)}

      {:ok, kind, _target_name, type} when kind in [:type, :atom, :integer] ->
        quoted_type =
          type
          |> Code.Typespec.type_to_quoted()
          |> target_type_quoted()
          |> clean_meta()

        {:ok, quoted_type, Enum.reverse(dereferenced_types)}

      {:error, _} = err ->
        err
    end
  end

  defp having_name(name, {_kind, {name, {target_kind, _, target_name, _}, _} = spec}),
    do: {:ok, target_kind, target_name, spec}

  defp having_name(name, {_kind, {name, {target_kind, _, _}, _} = spec}),
    do: {:ok, target_kind, nil, spec}

  defp having_name(_, _), do: nil

  defp target_type_quoted({:"::", _, [_name, quoted_type]}), do: quoted_type

  defp clean_remote_meta({{:., _meta1, aliases}, _meta2, arg3}), do: {{:., [], aliases}, [], arg3}
  defp clean_remote_meta({_keyword_or_as_boolean, _meta1, _} = term), do: clean_meta(term)

  defp clean_meta(term), do: Macro.update_meta(term, fn _meta -> [] end)
end
