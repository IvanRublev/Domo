defmodule Domo.TypeEnsurerFactory.Resolver.Fields do
  @moduledoc false

  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Alias
  alias Domo.TypeEnsurerFactory.ModuleInspector
  alias Domo.TermSerializer

  def resolve(mfe, preconds, remote_types_as_any, resolvable_structs) do
    {module, fields, env} = mfe

    {field_types, field_errors, all_deps} =
      Enum.reduce(fields, {%{}, [], []}, fn {field_name, quoted_type}, {field_types, field_errors, all_deps} ->
        resolved_types_table = []
        resolving_context = {env, preconds, remote_types_as_any, resolvable_structs, resolved_types_table}
        {types, errors, deps} = resolve_type(quoted_type, module, nil, resolving_context, {[], [], []})

        types =
          types
          |> Enum.reverse()
          |> Enum.uniq()

        updated_field_types = Map.put(field_types, field_name, types)

        {updated_field_types, errors ++ field_errors, all_deps ++ deps}
      end)

    struct_precondition = get_precondition(preconds, module, :t)

    {module, {field_types, struct_precondition}, field_errors, all_deps}
  end

  defdelegate preconditions_hash(types_precond_description), to: TermSerializer, as: :term_md5

  defp get_precondition(preconds, module, type_name) do
    preconds
    |> Map.get(module, [])
    |> Enum.find(&match?({^type_name, _description}, &1))
    |> cast_to_precondition(module)
  end

  defp cast_to_precondition(nil, _module) do
    nil
  end

  defp cast_to_precondition({type, description}, module) do
    Precondition.new(module: module, type_name: type, description: description)
  end

  # Literals

  defp resolve_type({:|, _meta, [arg1, arg2]} = type, module, precond, resolving_context, {types, errs, deps}) do
    if is_nil(precond) do
      {res_types, res_errs, res_deps} =
        resolve_type(
          arg1,
          module,
          nil,
          resolving_context,
          resolve_type(arg2, module, nil, resolving_context, {[], [], []})
        )

      # reject other options for any()
      res_types =
        res_types
        |> Enum.find(res_types, &match?({:any, _, _}, &1))
        |> List.wrap()

      or_type_precond =
        case res_types do
          [resolved_type1, resolved_type2] -> {quote(do: unquote(resolved_type1) | unquote(resolved_type2)), nil}
          [any_type] -> any_type
        end

      {[or_type_precond | types], res_errs ++ errs, res_deps ++ deps}
    else
      type_string = Macro.to_string(type)

      error =
        {:error,
         """
         Precondition for value of | or type is not allowed. You can extract each element \
         of #{type_string} type to @type definitions and set precond for each of it.\
         """}

      {types, [error | errs], deps}
    end
  end

  defp resolve_type([{:..., _meta, _arg}], module, precond, _env_preconds, {types, errs, deps}) do
    any_type = {:any, [], []}
    joint_type = {quote(context: module, do: nonempty_list(unquote(any_type))), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type([type, {:..., _meta2, _arg2}], module, precond, resolving_context, {types, errs, deps}) do
    {[el_type], el_errs, el_deps} = resolve_type(type, module, nil, resolving_context, {[], [], []})
    list_type_precond = {quote(context: module, do: nonempty_list(unquote(el_type))), precond}
    {[list_type_precond | types], el_errs ++ errs, el_deps ++ deps}
  end

  # Ecto.Schema Types

  defp resolve_type({{:., _, [Ecto.Schema, one_type]}, _, [type]}, module, precond, resolving_context, acc)
       when one_type in [:has_one, :embeds_one, :belongs_to] do
    do_resolve_ecto_schema(:one, one_type, type, module, precond, resolving_context, acc)
  end

  defp resolve_type(
         {{:., _, [{:__aliases__, _, [:Ecto, :Schema]}, one_type]}, _, [type]},
         module,
         precond,
         resolving_context,
         acc
       )
       when one_type in [:has_one, :embeds_one, :belongs_to] do
    do_resolve_ecto_schema(:one, one_type, type, module, precond, resolving_context, acc)
  end

  defp resolve_type({{:., _, [Ecto.Schema, many_type]}, _, [type]}, module, precond, resolving_context, acc)
       when many_type in [:has_many, :many_to_many, :embeds_many] do
    do_resolve_ecto_schema(:many, many_type, type, module, precond, resolving_context, acc)
  end

  defp resolve_type(
         {{:., _, [{:__aliases__, _, [:Ecto, :Schema]}, many_type]}, _, [type]},
         module,
         precond,
         resolving_context,
         acc
       )
       when many_type in [:has_many, :many_to_many, :embeds_many] do
    do_resolve_ecto_schema(:many, many_type, type, module, precond, resolving_context, acc)
  end

  # Remote Types

  defp resolve_type({{:., _, [rem_module, rem_type]}, _, _}, _module, precond, resolving_context, {types, errs, deps}) do
    {env, preconds_map, remote_types_as_any, resolvables, resolved_types_table} = resolving_context

    rem_module_alias =
      if is_atom(rem_module) and not Alias.erlang_module_atom?(rem_module) do
        {:__aliases__, [], [Alias.atom_drop_elixir_prefix(rem_module)]}
      else
        rem_module
      end

    rem_module = Macro.expand_once(rem_module_alias, env)

    cond do
      Enum.member?(resolved_types_table, {rem_module, rem_type}) ->
        err = {:error, {:self_referencing_type, Alias.string_by_concat(rem_module, rem_type) <> "()"}}
        {types, [err | errs], deps}

      Enum.member?(remote_types_as_any[rem_module] || [], rem_type) ->
        joint_type = {:any, [], []}
        {[joint_type | types], errs, deps}

      true ->
        rem_type_precond = get_precondition(preconds_map, rem_module, rem_type)

        with {:ok, type_list} <- ModuleInspector.beam_types(rem_module),
             {:ok, type, dereferenced_types} <- ModuleInspector.find_beam_type_quoted(rem_type, type_list),
             dereferenced_preconds = Enum.map(dereferenced_types, &get_precondition(preconds_map, rem_module, &1)),
             {:ok, precond} <- get_valid_precondition([precond, rem_type_precond | dereferenced_preconds]) do
          resolving_context = {env, preconds_map, remote_types_as_any, resolvables, [{rem_module, rem_type} | resolved_types_table]}
          resolve_type(type, rem_module, precond, resolving_context, {types, errs, [rem_module | deps]})
        else
          {:error, {:type_not_found, missing_type}} ->
            err = {:error, {:type_not_found, {rem_module, missing_type, Alias.string_by_concat(rem_module, rem_type) <> "()"}}}
            {types, [err | errs], deps}

          {:error, {:parametrized_type_not_supported, _parametrized_type}} ->
            err = {:error, {:parametrized_type_not_supported, {rem_module, Alias.string_by_concat(rem_module, rem_type) <> "()"}}}
            {types, [err | errs], deps}

          {:error, :no_types_registered} ->
            err = {:error, {:no_types_registered, Alias.string_by_concat(rem_module, rem_type) <> "()"}}
            {types, [err | errs], deps}

          {:error, _} = err ->
            {types, [err | errs], deps}
        end
    end
  end

  # Basic and Built-in Types

  defp resolve_type({:boolean = kind, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    if is_nil(precond) do
      joint_type =
        or_type_quoted(
          [
            true,
            false
          ],
          module,
          [nil]
        )

      {[joint_type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(kind)}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:identifier = kind, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    if is_nil(precond) do
      joint_type =
        or_type_quoted(
          [
            quote(context: module, do: pid()),
            quote(context: module, do: reference()),
            quote(context: module, do: port())
          ],
          module,
          [nil, nil]
        )

      {[joint_type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(kind)}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:iodata = kind, _meta, _args}, module, precond, resolving_context, {types, errs, deps} = acc) do
    if is_nil(precond) do
      resolve_type(
        quote(context: module, do: binary() | iolist()),
        module,
        nil,
        resolving_context,
        acc
      )
    else
      error = {:error, precondition_not_supported_message(kind)}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:iolist = kind, _meta, _args}, module, precond, resolving_context, {types, errs, deps} = acc) do
    if is_nil(precond) do
      resolve_type(
        quote(context: module, do: maybe_improper_list(byte() | binary(), binary() | [])),
        module,
        nil,
        resolving_context,
        acc
      )
    else
      error = {:error, precondition_not_supported_message(kind)}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:number, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    joint_type =
      or_type_quoted(
        [
          {drop_line_metadata({:integer, [], []}), nil},
          {drop_line_metadata({:float, [], []}), nil}
        ],
        module,
        [precond]
      )

    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:timeout = kind, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    if is_nil(precond) do
      joint_type =
        or_type_quoted(
          [
            :infinity,
            {quote(context: module, do: non_neg_integer()), nil}
          ],
          module,
          [nil]
        )

      {[joint_type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(kind)}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({type, _meta, _args}, module, precond, _env_preconds, {types, errs, deps})
       when type in [:arity, :byte] do
    joint_type = {quote(context: module, do: 0..255), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:binary, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {quote(context: module, do: <<_::_*8>>), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:bitstring, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    # credo:disable-for-next-line
    joint_type = {quote(context: module, do: <<_::_*1>>), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:char, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {quote(context: module, do: 0..0x10FFFF), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:charlist, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {quote(context: module, do: [{0..0x10FFFF, nil}]), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:nonempty_charlist, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {quote(context: module, do: nonempty_list({0..0x10FFFF, nil})), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({type, _meta, _args}, module, precond, _env_preconds, {types, errs, deps})
       when type in [:fun, :function] do
    joint_type = {quote(context: module, do: (... -> any)), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:list, _meta, []}, _module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {[{:any, [], []}], precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:nonempty_list, _meta, []}, module, precond, _env_preconds, {types, errs, deps}) do
    any_type_precond = {:any, [], []}
    joint_type = {quote(context: module, do: nonempty_list(unquote(any_type_precond))), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({maybe_list_kind, _meta, []}, module, precond, _env_preconds, {types, errs, deps})
       when maybe_list_kind in [:maybe_improper_list, :nonempty_maybe_improper_list] do
    any = {:any, [], []}
    joint_type = {quote(context: module, do: unquote(maybe_list_kind)(unquote(any), unquote(any))), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:mfa, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {quote(context: module, do: {{atom(), nil}, {atom(), nil}, {0..255, nil}}), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({type, _meta, _args}, module, precond, _env_preconds, {types, errs, deps})
       when type in [:module, :node] do
    joint_type = {quote(context: module, do: atom()), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:struct, _meta, _args}, module, precond, _env_preconds, {types, errs, deps}) do
    struct_attribute = ModuleInspector.struct_attribute()
    any = {:any, [], []}

    joint_type = {
      quote(context: module, do: %{unquote(struct_attribute) => {atom(), nil}, optional({atom(), nil}) => unquote(any)}),
      precond
    }

    {[joint_type | types], errs, deps}
  end

  defp resolve_type({type, _meta, _args}, module, precond, _env_preconds, {types, errs, deps})
       when type in [:none, :no_return] do
    if is_nil(precond) do
      quoted_type = quote(context: module, do: {})
      {[quoted_type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(type)}
      {types, [error | errs], deps}
    end
  end

  # Parametrized literals, basic, and built-in types

  defp resolve_type({:keyword, _meta, []}, module, precond, _env_preconds, {types, errs, deps}) do
    atom_precond = {{:atom, [], []}, nil}
    any = {:any, [], []}
    joint_type = {quote(context: module, do: [{unquote(atom_precond), unquote(any)}]), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:keyword, _meta, [type]}, module, precond, resolving_context, {types, errs, deps}) do
    if is_nil(precond) do
      {[el_type], el_errs, el_deps} = resolve_type(type, module, nil, resolving_context, {[], [], []})

      atom_precond = {{:atom, [], []}, nil}
      kw_type = quote(context: module, do: [{unquote(atom_precond), unquote(el_type)}])
      {[{kw_type, precond} | types], el_errs ++ errs, el_deps ++ deps}
    else
      error =
        {:error,
         """
         Precondition for value of keyword(t) type is not allowed. \
         You can extract t as a user @type and define precondition for it.\
         """}

      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:list, _meta, [arg]}, module, precond, resolving_context, acc) do
    resolve_type([arg], module, precond, resolving_context, acc)
  end

  defp resolve_type({:nonempty_list, _meta, [arg]}, module, precond, resolving_context, {types, errs, deps}) do
    {[el_type], el_err, el_deps} = resolve_type(arg, module, nil, resolving_context, {[], [], []})
    list_type_precond = {quote(context: module, do: nonempty_list(unquote(el_type))), precond}
    {[list_type_precond | types], el_err ++ errs, el_deps ++ deps}
  end

  defp resolve_type({:as_boolean, _meta, [type]}, module, precond, resolving_context, {types, errs, deps} = acc) do
    if is_nil(precond) do
      resolve_type(type, module, nil, resolving_context, acc)
    else
      error =
        {:error,
         """
         Precondition for value of as_boolean(t) type is not allowed. \
         You can extract t as a user @type and define precondition for it.\
         """}

      {types, [error | errs], deps}
    end
  end

  defp resolve_type([{:->, _meta, [[], _]}] = type, _module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {type, precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type([{:->, _meta, [[{:..., _, _}], _]}] = type, _module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {type, precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type([{:->, _meta, [[_ | _] = args, _return_type]}], module, precond, resolving_context, {types, errs, deps}) do
    {el_types, el_errs, el_deps} = parallel_resolve_type(Enum.reverse(args), module, nil, resolving_context, {[], [], []})
    any = {:any, [], []}
    fun_type_precond = {quote(context: module, do: (unquote_splicing(el_types) -> unquote(any))), precond}
    {[fun_type_precond | types], el_errs ++ errs, el_deps ++ deps}
  end

  defp resolve_type({:%{}, _meta, [{{kind, _, [_key]}, _value} | _] = kkv}, module, precond, resolving_context, {types, errs, deps})
       when kind in [:required, :optional] do
    {resolved_kv, resolved_errs, resolved_deps} =
      kkv
      |> Enum.map(fn {{_kind, _, [key]}, value} -> {key, value} end)
      |> (&quote(context: module, do: %{unquote_splicing(&1)})).()
      |> resolve_type(module, precond, resolving_context, {[], [], []})

    joint_types =
      Enum.map(resolved_kv, fn {{:%{}, _meta, kv_list}, precond} ->
        args =
          for {{key, value}, idx} <- Enum.with_index(kv_list) do
            {{kind, _, [_key]}, _value} = Enum.at(kkv, idx)
            {{kind, [], [key]}, value}
          end

        {quote(context: module, do: %{unquote_splicing(args)}), precond}
      end)

    {joint_types ++ types, resolved_errs ++ errs, deps ++ resolved_deps}
  end

  defp resolve_type({:%{}, _meta, [{_key, _value} | _] = kv_list}, module, precond, resolving_context, {types, errs, deps}) do
    {el_types, el_errs, el_deps} =
      kv_list
      |> Enum.reverse()
      |> Enum.reduce({[], [], []}, fn {key, value}, {types, errs, deps} ->
        {[key_type], key_errs, key_deps} = resolve_type(key, module, nil, resolving_context, {[], [], []})
        {[value_type], value_errs, value_deps} = resolve_type(value, module, nil, resolving_context, {[], [], []})

        {[{key_type, value_type} | types], key_errs ++ value_errs ++ errs, key_deps ++ value_deps ++ deps}
      end)

    map_type_precond = {{:%{}, [], el_types}, precond}
    {[map_type_precond | types], el_errs ++ errs, el_deps ++ deps}
  end

  defp resolve_type(
         {:%, _meta, [struct_alias, {:%{}, _kvm, [{_key, _value} | _]}]},
         module,
         field_precond,
         resolving_context,
         {types, errs, deps}
       ) do
    {_env, preconds, _remote_types_as_any, resovable_structs, _resolved_types_table} = resolving_context
    struct_module = Alias.alias_to_atom(struct_alias)
    t_precond = get_precondition(preconds, struct_module, :t)
    precond = t_precond || field_precond

    if ensurable_struct?(struct_module, resovable_structs) do
      joint_type = {
        quote(context: module, do: %unquote(Alias.atom_to_alias(struct_alias)){}),
        precond
      }

      {[joint_type | types], errs, deps}
    else
      struct_module_name = Alias.atom_to_string(struct_module)

      error = """
      Consider to use Domo in #{struct_module_name} struct for validation speed.
      If you don't own the struct you can define custom user type and validate fields \
      in the precondition function attached like the following:

          @type unowned_struct :: term()
          precond unowned_struct: &validate_unowned_struct/1

          def validate_unowned_struct(value) do
            case value do
              %#{struct_module_name}{} -> if ...validate fields here..., do: :ok, else: {:error, "expected valid fields in #{struct_module_name} struct."}
              _ -> {:error, "expected #{struct_module_name} struct value."}
            end
          end

      Alternatively you can instruct Domo to treat #{struct_module_name}.t() as any() \
      by specifying `remote_types_as_any: [{#{struct_module_name}, :t}]` \
      as global `config :domo` or as `use Domo` option. \
      More details are in docs for `__using__/1` macro.
      """

      {types, [error | errs], deps}
    end
  end

  defp resolve_type([{key, _value} | _] = list, module, precond, resolving_context, {types, errs, deps}) when is_atom(key) do
    keyword? =
      Enum.all?(list, fn
        {key, _value} -> is_atom(key)
        _ -> false
      end)

    if keyword? do
      {keys, value_types} = Enum.unzip(list)
      {resolved_value_types, resolved_errs, resolved_deps} = parallel_resolve_type(value_types, module, nil, resolving_context, {[], [], []})
      kv_types = Enum.zip(keys, resolved_value_types)

      {[{kv_types, precond} | types], resolved_errs ++ errs, resolved_deps ++ deps}
    else
      {types, [:keyword_list_should_has_atom_keys | errs], deps}
    end
  end

  defp resolve_type([el], module, precond, resolving_context, {types, errs, deps}) do
    {[el_type], el_errs, el_deps} = resolve_type(el, module, nil, resolving_context, {[], [], []})
    {[{[el_type], precond} | types], el_errs ++ errs, el_deps ++ deps}
  end

  defp resolve_type({list_kind, _meta, [_head_type, _tail_type] = ht_types}, module, precond, resolving_context, {types, errs, deps})
       when list_kind in [
              :maybe_improper_list,
              :nonempty_improper_list,
              :nonempty_maybe_improper_list
            ] do
    {[head_type, tail_type], el_errs, el_deps} = parallel_resolve_type(Enum.reverse(ht_types), module, nil, resolving_context, {[], [], []})

    list_type_precond = {
      quote(
        context: module,
        do: unquote(list_kind)(unquote(head_type), unquote(tail_type))
      ),
      precond
    }

    {[list_type_precond | types], el_errs ++ errs, el_deps ++ deps}
  end

  defp resolve_type({:{} = kind, _meta, []}, module, precond, _env_preconds, {types, errs, deps}) do
    if is_nil(precond) do
      joint_type = quote(context: module, do: {})
      {[joint_type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(to_string(kind))}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:{}, _meta, [_ | _] = args}, module, precond, resolving_context, {types, errs, deps}) do
    {el_types, el_errs, el_deps} = parallel_resolve_type(Enum.reverse(args), module, nil, resolving_context, {[], [], []})
    tuple_type_precond = {quote(context: module, do: {unquote_splicing(el_types)}), precond}
    {[tuple_type_precond | types], el_errs ++ errs, el_deps ++ deps}
  end

  defp resolve_type({arg1, arg2}, module, precond, resolving_context, {types, errs, deps}) do
    {[arg1_type, arg2_type], el_errs, el_deps} = parallel_resolve_type([arg2, arg1], module, nil, resolving_context, {[], [], []})
    tuple_type_precond = {quote(context: module, do: {unquote(arg1_type), unquote(arg2_type)}), precond}
    {[tuple_type_precond | types], el_errs ++ errs, el_deps ++ deps}
  end

  defp resolve_type({kind_any, _meta, args}, _module, precond, _env_preconds, {_types, errs, deps})
       when kind_any in [:term, :any] do
    # we use this hack because for any as a type parameter and any from an external field type with precondition
    type = if is_nil(precond), do: {:any, [], args}, else: {{:any, [], args}, precond}
    {[type], errs, deps}
  end

  defp resolve_type(_type, _module, _precond, _env_preconds, {[{:any, _, _}], _errs, _deps} = acc) do
    acc
  end

  defp resolve_type({type_name, _, []} = type, _module, precond, _env_preconds, {types, errs, deps})
       when type_name in [
              :<<>>,
              :%{}
            ] do
    if is_nil(precond) do
      type = drop_line_metadata(type)
      {[type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(to_string(type_name))}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({type_name, _, []} = type, _module, precond, _env_preconds, {types, errs, deps})
       when type_name in [
              :port,
              :pid,
              :reference
            ] do
    if is_nil(precond) do
      type = drop_line_metadata(type)
      {[type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(type_name)}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({:<<>> = type_name, _, [{:"::", _, [_, 0]}]} = type, _module, precond, _env_preconds, {types, errs, deps}) do
    if is_nil(precond) do
      type = drop_line_metadata(type)
      {[type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(to_string(type_name))}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type({type_name, _, _} = type, _module, precond, _env_preconds, {types, errs, deps})
       when type_name in [
              :<<>>,
              :%,
              :..,
              :-,
              :float,
              :atom,
              :integer,
              :neg_integer,
              :non_neg_integer,
              :pos_integer,
              :tuple,
              :map
            ] do
    joint_type = {drop_line_metadata(type), precond}
    {[joint_type | types], errs, deps}
  end

  defp resolve_type({:"::", _, [_var_name, type]}, module, precond, resolving_context, acc) do
    resolve_type(type, module, precond, resolving_context, acc)
  end

  defp resolve_type({type_name, _, _}, module, precond, resolving_context, {types, errs, deps} = acc) do
    {env, preconds_map, remote_types_as_any, resolvables, resolved_types_table} = resolving_context
    type_precond = get_precondition(preconds_map, module, type_name)

    cond do
      Enum.member?(resolved_types_table, {module, type_name}) ->
        err = {:error, {:self_referencing_type, Alias.string_by_concat(module, type_name) <> "()"}}
        {types, [err | errs], deps}

      Enum.member?(remote_types_as_any[module] || [], type_name) ->
        joint_type = {:any, [], []}
        {[joint_type | types], errs, deps}

      true ->
        with {:ok, type_list} <- ModuleInspector.beam_types(module),
             {:ok, type, dereferenced_types} <- ModuleInspector.find_beam_type_quoted(type_name, type_list),
             dereferenced_preconds = Enum.map(dereferenced_types, &get_precondition(preconds_map, module, &1)),
             {:ok, precond} <- get_valid_precondition([precond, type_precond | dereferenced_preconds]) do
          resolving_context = {env, preconds_map, remote_types_as_any, resolvables, [{module, type_name} | resolved_types_table]}
          resolve_type(type, module, precond, resolving_context, acc)
        else
          {:error, {:type_not_found, missing_type}} ->
            err = {:error, {:type_not_found, {Alias.alias_to_atom(module), missing_type, Alias.string_by_concat(module, type_name) <> "()"}}}
            {types, [err | errs], deps}

          {:error, {:parametrized_type_not_supported, _parametrized_type}} ->
            err = {:error, {:parametrized_type_not_supported, {Alias.alias_to_atom(module), Alias.string_by_concat(module, type_name) <> "()"}}}
            {types, [err | errs], deps}

          {:error, _} = err ->
            {types, [err | errs], deps}
        end
    end
  end

  defp resolve_type(type, _module, precond, _env_preconds, {types, errs, deps})
       when is_number(type) or is_atom(type) or type == [] do
    if is_nil(precond) do
      not_preconditionable_type = type
      {[not_preconditionable_type | types], errs, deps}
    else
      error = {:error, precondition_not_supported_message(inspect(type))}
      {types, [error | errs], deps}
    end
  end

  defp resolve_type(type, _module, precond, _env_preconds, {types, errs, deps}) do
    joint_type = {type, precond}
    {[joint_type | types], errs, deps}
  end

  defp do_resolve_ecto_schema(schema_kind, schema_type, type, module, precond, resolving_context, {types, errs, deps} = acc) do
    type_to_resolve =
      case schema_kind do
        :one -> quote(do: unquote(type) | Ecto.Association.NotLoaded.t())
        :many -> quote(do: [unquote(type)] | Ecto.Association.NotLoaded.t())
      end

    if is_nil(precond) do
      {types, errors, deps} =
        resolve_type(
          type_to_resolve,
          module,
          precond,
          resolving_context,
          acc
        )

      {types, errors, deps}
    else
      error =
        {:error,
         """
         Precondition for value of Ecto.Schema.#{Atom.to_string(schema_type)}(t) type is not allowed.\
         """}

      {types, [error | errs], deps}
    end
  end

  # this one is for internal cases when we have several arguments to be resolved, f.e. from {a, b, c}
  # it resolves each element independently so f.e. :any as one resolved element doesn't affect others
  defp parallel_resolve_type([_ | _] = list, module, nil, resolving_context, acc) do
    Enum.reduce(list, acc, fn type, {types, errs, deps} ->
      {el_type, el_errs, el_deps} = resolve_type(type, module, nil, resolving_context, {[], [], []})
      {el_type ++ types, el_errs ++ errs, el_deps ++ deps}
    end)
  end

  defp or_type_quoted(types, module, preconds) when length(preconds) == length(types) - 1 do
    do_or_type_quoted(types, module, preconds)
  end

  defp do_or_type_quoted([type_head], module, []) do
    quote(context: module, do: unquote(type_head))
  end

  defp do_or_type_quoted([type_head | type_tail], module, [precond_head | precond_tail]) do
    quote(context: module, do: {unquote(type_head) | unquote(or_type_quoted(type_tail, module, precond_tail)), unquote(precond_head)})
  end

  defp get_valid_precondition(preconditions) do
    preconditions = Enum.reject(preconditions, &is_nil/1)

    if Enum.count(preconditions) >= 2 do
      refferal_precond = Enum.at(preconditions, 0)
      refferring_precond = Enum.at(preconditions, 1)
      refferal_type = Alias.string_by_concat(refferal_precond.module, refferal_precond.type_name) <> "()"
      refferring_type = Alias.string_by_concat(refferring_precond.module, refferring_precond.type_name) <> "()"

      {:error,
       """
       Precondition conflict for types #{refferal_type} and #{refferring_type} \
       referring one another. You can define only one precondition for either type.\
       """}
    else
      {:ok, List.first(preconditions)}
    end
  end

  defp precondition_not_supported_message(type) do
    type_string = if is_binary(type), do: type, else: to_string(type) <> "()"
    "Precondition for value of #{type_string} type is not allowed."
  end

  defp drop_line_metadata(type), do: Macro.update_meta(type, &Keyword.delete(&1, :line))

  defp ensurable_struct?(module, resolvable_structs) do
    MapSet.member?(resolvable_structs, module) or ModuleInspector.has_type_ensurer?(module)
  end
end
