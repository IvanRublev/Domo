defmodule Domo.TypeEnsurerFactory.ModuleInspector do
  @moduledoc false

  @spec module_context?(Env.t()) :: true | false
  def module_context?(env) do
    not is_nil(env.module) and is_nil(env.function)
  end

  @spec beam_types(module(), fun(), fun()) ::
          {:ok, [tuple()]} | {:error, {:no_beam_file, module()}}
  def beam_types(
        module,
        load_module \\ &Code.ensure_loaded/1,
        fetch_types \\ &Code.Typespec.fetch_types/1
      ) do
    with {:module, module} <- load_module.(module),
         {:ok, _type_list} = reply <- fetch_types.(module) do
      reply
    else
      _ -> {:error, {:no_beam_file, module}}
    end
  end

  @spec find_type_quoted(atom, [tuple()]) ::
          {:ok, {atom(), Macro.t()}} | {:error, {:type_not_found, atom()}}
  def find_type_quoted(name, type_list) do
    notfound = {:error, {:type_not_found, name}}

    case Enum.find_value(type_list, notfound, &having_name(name, &1)) do
      {:ok, :user_type, target_name, _type} ->
        find_type_quoted(target_name, type_list)

      {:ok, :remote_type, _target_name, type} ->
        {:ok,
         type
         |> Code.Typespec.type_to_quoted()
         |> target_type_quoted()
         |> clean_remote_meta()}

      {:ok, :type, _target_name, type} ->
        {:ok,
         type
         |> Code.Typespec.type_to_quoted()
         |> target_type_quoted()
         |> clean_meta()}

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

  defp clean_remote_meta({{:., _meta, aliases}, _meta2, arg3}), do: {{:., [], aliases}, [], arg3}

  defp clean_meta(term), do: Macro.update_meta(term, fn _meta -> [] end)
end
