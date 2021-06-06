defmodule Domo.TypeEnsurerFactory.ModuleInspector do
  @moduledoc false

  def module_context?(env) do
    not is_nil(env.module) and is_nil(env.function)
  end

  def beam_types_hash(module) do
    case beam_types(module) do
      {:ok, type_list} -> type_list |> :erlang.term_to_binary() |> :erlang.md5()
      _error -> nil
    end
  end

  def beam_types(module, load_module \\ &Code.ensure_loaded/1, fetch_types \\ &Code.Typespec.fetch_types/1) do
    with {:module, module} <- load_module.(module),
         {:ok, type_list} <- fetch_types.(module) do
      only_direct_type_list =
        type_list
        |> Enum.reject(&parametrized_type?/1)
        |> Enum.into([])

      {:ok, only_direct_type_list}
    else
      _ -> {:error, {:no_beam_file, module}}
    end
  end

  defp parametrized_type?({:type, {_name, _definition, [_ | _] = _arg_list}}) do
    true
  end

  defp parametrized_type?(_type) do
    false
  end

  def find_type_quoted(name, type_list, dereferenced_types \\ []) do
    notfound = {:error, {:type_not_found, name}}

    case Enum.find_value(type_list, notfound, &having_name(name, &1)) do
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
