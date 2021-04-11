defmodule Domo.TypeEnsurerFactory.Resolver.Fields do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.Resolver.Fields.Arguments
  alias Domo.TypeEnsurerFactory.ModuleInspector

  @spec resolve(module, map, Macro.env()) ::
          {module, %{required(atom) => list}, [{:error, any()}], [module]}
  def resolve(module, fields, env) do
    {field_types, field_errors, all_deps} =
      Enum.reduce(fields, {%{}, [], []}, fn {field_name, quoted_type},
                                            {field_types, field_errors, all_deps} ->
        {types, errors, deps} = resolve_type(quoted_type, module, env, {[], [], []})

        types =
          types
          |> Enum.reverse()
          |> Enum.uniq()

        {Map.put(field_types, field_name, types), errors ++ field_errors, all_deps ++ deps}
      end)

    {module, field_types, field_errors, all_deps}
  end

  # Literals

  @type types_errs_deps :: {[Macro.t()], [{:error, any()}], [module]}

  @spec resolve_type(Macro.t(), module, Macro.env(), types_errs_deps()) :: types_errs_deps()
  defp resolve_type({:|, _meta, [arg1, arg2]}, module, env, acc) do
    resolve_type(arg2, module, env, resolve_type(arg1, module, env, acc))
  end

  defp resolve_type([{:..., _meta, _arg}], module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: nonempty_list(any())) | types], errs, deps}

  defp resolve_type([type, {:..., _meta2, _arg2}], module, env, acc) do
    combine_or_args(
      [type],
      module,
      env,
      fn [type] -> quote(context: module, do: nonempty_list(unquote(type))) end,
      acc
    )
  end

  # Remote Types

  defp resolve_type(
         {{:., _, [rem_module, rem_type]}, _, _},
         _module,
         env,
         {types, errs, deps}
       ) do
    rem_module = Macro.expand_once(rem_module, env)

    with {:ok, type_list} <- ModuleInspector.beam_types(rem_module),
         {:ok, type} <- ModuleInspector.find_type_quoted(rem_type, type_list) do
      resolve_type(type, rem_module, env, {types, errs, [rem_module | deps]})
    else
      {:error, _} = err -> {types, [err | errs], deps}
    end
  end

  # Basic and Built-in Types

  defp resolve_type({:boolean, _meta, _args}, module, _env, {types, errs, deps}) do
    {[quote(context: module, do: true), quote(context: module, do: false) | types], errs, deps}
  end

  defp resolve_type({:identifier, _meta, _args}, module, _env, {types, errs, deps}) do
    {[
       quote(context: module, do: reference()),
       quote(context: module, do: port()),
       quote(context: module, do: pid()) | types
     ], errs, deps}
  end

  defp resolve_type({:iodata, _meta, _args}, module, env, acc) do
    resolve_type(quote(context: module, do: binary() | iolist()), module, env, acc)
  end

  defp resolve_type({:iolist, _meta, _args}, module, env, acc) do
    resolve_type(
      quote(context: module, do: maybe_improper_list(byte() | binary(), binary() | [])),
      module,
      env,
      acc
    )
  end

  defp resolve_type({:number, _meta, _args}, module, _env, {types, errs, deps}) do
    {[
       quote(context: module, do: float()),
       quote(context: module, do: integer()) | types
     ], errs, deps}
  end

  defp resolve_type({:timeout, _meta, _args}, module, _env, {types, errs, deps}) do
    {[
       quote(context: module, do: non_neg_integer()),
       quote(context: module, do: :infinity) | types
     ], errs, deps}
  end

  defp resolve_type({type, _meta, _args}, module, _env, {types, errs, deps})
       when type in [:arity, :byte],
       do: {[quote(context: module, do: 0..255) | types], errs, deps}

  defp resolve_type({:binary, _meta, _args}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: <<_::_*8>>) | types], errs, deps}

  defp resolve_type({:bitstring, _meta, _args}, module, _env, {types, errs, deps}),
    # credo:disable-for-next-line
    do: {[quote(context: module, do: <<_::_*1>>) | types], errs, deps}

  defp resolve_type({:char, _meta, _args}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: 0..0x10FFFF) | types], errs, deps}

  defp resolve_type({:charlist, _meta, _args}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: [0..0x10FFFF]) | types], errs, deps}

  defp resolve_type({:nonempty_charlist, _meta, _args}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: nonempty_list(0..0x10FFFF)) | types], errs, deps}

  defp resolve_type({type, _meta, _args}, module, _env, {types, errs, deps})
       when type in [:fun, :function],
       do: {[quote(context: module, do: (... -> any)) | types], errs, deps}

  defp resolve_type({:list, _meta, []}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: [any()]) | types], errs, deps}

  defp resolve_type({:nonempty_list, _meta, []}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: nonempty_list(any())) | types], errs, deps}

  defp resolve_type({maybe_list_kind, _meta, []}, module, _env, {types, errs, deps})
       when maybe_list_kind in [:maybe_improper_list, :nonempty_maybe_improper_list],
       do:
         {[quote(context: module, do: unquote(maybe_list_kind)(any(), any())) | types], errs,
          deps}

  defp resolve_type({:mfa, _meta, _args}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: {module(), atom(), 0..255}) | types], errs, deps}

  defp resolve_type({type, _meta, _args}, module, _env, {types, errs, deps})
       when type in [:module, :node],
       do: {[quote(context: module, do: atom()) | types], errs, deps}

  defp resolve_type({:struct, _meta, _args}, module, _env, {types, errs, deps}),
    do:
      {[quote(context: module, do: %{:__struct__ => atom(), optional(atom()) => any()}) | types],
       errs, deps}

  defp resolve_type({type, _meta, _args}, module, _env, {types, errs, deps})
       when type in [:none, :no_return],
       do: {[quote(context: module, do: {}) | types], errs, deps}

  # Parametrized literals, basic, and built-in types

  defp resolve_type({:keyword, _meta, []}, module, _env, {types, errs, deps}),
    do: {[quote(context: module, do: [{atom(), any()}]) | types], errs, deps}

  defp resolve_type({:keyword, _meta, [type]}, module, env, acc) do
    combine_or_args(
      [type],
      module,
      env,
      fn [type] -> quote(context: module, do: [{atom(), unquote(type)}]) end,
      acc
    )
  end

  defp resolve_type({:list, _meta, [arg]}, module, env, acc) do
    combine_or_args([arg], module, env, &quote(context: module, do: unquote(&1)), acc)
  end

  defp resolve_type({:nonempty_list, _meta, [arg]}, module, env, acc) do
    combine_or_args(
      [arg],
      module,
      env,
      fn [arg] -> quote(context: module, do: nonempty_list(unquote(arg))) end,
      acc
    )
  end

  defp resolve_type({:as_boolean, _meta, [type]}, module, env, acc) do
    combine_or_args(
      [type],
      module,
      env,
      fn [type] -> quote(context: module, do: unquote(type)) end,
      acc
    )
  end

  defp resolve_type([{:->, _meta, [[], _]}] = type, _module, _env, {types, errs, deps}),
    do: {[type | types], errs, deps}

  defp resolve_type(
         [{:->, _meta, [[{:..., _, _}], _]}] = type,
         _module,
         _env,
         {types, errs, deps}
       ),
       do: {[type | types], errs, deps}

  defp resolve_type([{:->, _meta, [[_ | _] = args, _return_type]}], module, env, acc) do
    combine_or_args(
      args,
      module,
      env,
      &quote(context: module, do: (unquote_splicing(&1) -> any())),
      acc
    )
  end

  defp resolve_type({:%{}, _meta, [{{kind, _km, [key_type]}, value_type}]}, module, env, acc) do
    combine_or_args(
      [key_type, value_type],
      module,
      env,
      fn [key_type, value_type] ->
        quote(context: module, do: %{unquote(kind)(unquote(key_type)) => unquote(value_type)})
      end,
      acc
    )
  end

  defp resolve_type(
         {:%{}, _meta, [{{kind, _, [_key]}, _value} | _] = kkv},
         module,
         env,
         {types, errs, deps}
       )
       when kind in [:required, :optional] do
    {resolved_kv, resolved_errs, resolved_deps} =
      kkv
      |> Enum.map(fn {{_kind, _, [key]}, value} -> {key, value} end)
      |> (&quote(context: module, do: %{unquote_splicing(&1)})).()
      |> resolve_type(module, env, {[], [], []})

    {resolved_kv
     |> Enum.map(fn {:%{}, _meta, kv_list} ->
       args =
         for {{key, value}, idx} <- Enum.with_index(kv_list) do
           {{kind, _, [_key]}, _value} = Enum.at(kkv, idx)
           {{kind, [], [key]}, value}
         end

       quote(context: module, do: %{unquote_splicing(args)})
     end)
     |> Kernel.++(types), resolved_errs ++ errs, deps ++ resolved_deps}
  end

  defp resolve_type({:%{}, _meta, [{_key, _value} | _] = kv_list}, module, env, acc) do
    combine_or_args(
      kv_list,
      module,
      env,
      &quote(context: module, do: %{unquote_splicing(&1)}),
      acc
    )
  end

  defp resolve_type(
         {:%, _meta, [struct_alias, {:%{}, _kvm, [{_key, _value} | _] = kv_list}]},
         module,
         env,
         acc
       ) do
    combine_or_args(
      kv_list,
      module,
      env,
      &quote(
        context: module,
        do: %unquote(Alias.atom_to_alias(struct_alias)){unquote_splicing(&1)}
      ),
      acc
    )
  end

  defp resolve_type([_] = args, module, env, acc) do
    combine_or_args(args, module, env, &quote(context: module, do: [unquote_splicing(&1)]), acc)
  end

  defp resolve_type([_ | _] = list, module, env, {types, errs, deps} = acc) do
    keyword? =
      Enum.all?(list, fn
        {key, _value} -> is_atom(key)
        _ -> false
      end)

    if keyword? do
      combine_or_args(list, module, env, &quote(context: module, do: [unquote_splicing(&1)]), acc)
    else
      {types, [:keyword_list_should_has_atom_keys | errs], deps}
    end
  end

  defp resolve_type({list_kind, _meta, [_elem_type, _tail_type] = el_types}, module, env, acc)
       when list_kind in [
              :maybe_improper_list,
              :nonempty_improper_list,
              :nonempty_maybe_improper_list
            ] do
    combine_or_args(
      el_types,
      module,
      env,
      fn [elem_type, tail_type] ->
        quote(
          context: module,
          do: unquote(list_kind)(unquote(elem_type), unquote(tail_type))
        )
      end,
      acc
    )
  end

  defp resolve_type({:{}, _meta, []}, module, _env, {types, errs, deps}) do
    {[quote(context: module, do: {}) | types], errs, deps}
  end

  defp resolve_type({:{}, _meta, [_ | _] = args}, module, env, acc) do
    combine_or_args(args, module, env, &quote(context: module, do: {unquote_splicing(&1)}), acc)
  end

  defp resolve_type({arg1, arg2}, module, env, acc) do
    combine_or_args(
      [arg1, arg2],
      module,
      env,
      fn [arg1, arg2] -> quote(context: module, do: {unquote(arg1), unquote(arg2)}) end,
      acc
    )
  end

  defp resolve_type({kind_any, _meta, args}, _module, _env, {_types, errs, deps})
       when kind_any in [:term, :any],
       do: {[{:any, [], args}], errs, deps}

  defp resolve_type(_type, _module, _env, {[{:any, arg1, arg2}], errs, deps}),
    do: {[{:any, arg1, arg2}], errs, deps}

  defp resolve_type({type_name, _, _} = type, _module, _env, {types, errs, deps})
       when type_name in [
              :<<>>,
              :%,
              :..,
              :%{},
              :float,
              :atom,
              :integer,
              :neg_integer,
              :non_neg_integer,
              :pos_integer,
              :port,
              :pid,
              :reference,
              :tuple,
              :map
            ] do
    {[drop_line_metadata(type) | types], errs, deps}
  end

  defp resolve_type({type_name, _, _}, module, env, {types, errs, deps} = acc) do
    with {:ok, type_list} <- ModuleInspector.beam_types(module),
         {:ok, type} <- ModuleInspector.find_type_quoted(type_name, type_list) do
      resolve_type(type, module, env, acc)
    else
      err -> {types, [err | errs], deps}
    end
  end

  defp resolve_type(type, _module, _env, {types, errs, deps}) do
    {[type | types], errs, deps}
  end

  @spec combine_or_args(list(), module(), Macro.env(), fun(), types_errs_deps()) ::
          types_errs_deps()
  defp combine_or_args(args, module, env, quote_fn, {types, errs, deps}) do
    {args_resolved, errs_resolved, deps_resolved} =
      args
      |> Enum.map(&resolve_type(&1, module, env, {[], [], []}))
      |> Enum.reduce({[], [], []}, fn {args_el, errs_el, deps_el},
                                      {args_resolved, errs_resolved, deps_resolved} ->
        {[args_el | args_resolved], [errs_el | errs_resolved], [deps_el | deps_resolved]}
      end)

    {args_resolved, errs_resolved, deps_resolved} =
      {Enum.reverse(args_resolved), Enum.reverse(errs_resolved), Enum.reverse(deps_resolved)}

    {args_resolved
     |> Arguments.all_combinations()
     |> Enum.map(&quote_fn.(&1))
     |> Kernel.++(types), List.flatten(errs_resolved) ++ errs,
     deps ++ List.flatten(deps_resolved)}
  end

  defp drop_line_metadata(type), do: Macro.update_meta(type, &Keyword.delete(&1, :line))
end
