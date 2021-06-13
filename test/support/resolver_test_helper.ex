defmodule ResolverTestHelper do
  @moduledoc false

  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias Domo.TypeEnsurerFactory.ResolvePlanner

  @project_stub MixProjectStubCorrect

  def setup_project_planner(_context) do
    plan_file = DomoMixTask.manifest_path(@project_stub, :plan)
    types_file = DomoMixTask.manifest_path(@project_stub, :types)
    deps_file = DomoMixTask.manifest_path(@project_stub, :deps)
    preconds_file = DomoMixTask.manifest_path(@project_stub, :preconds)

    stop_project_palnner()

    {:ok, _pid} = ResolvePlanner.start(plan_file, preconds_file)

    ExUnit.Callbacks.on_exit(fn ->
      stop_project_palnner()
    end)

    %{
      planner: plan_file,
      project_stub: @project_stub,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    }
  end

  def stop_project_palnner do
    plan_file = DomoMixTask.manifest_path(@project_stub, :plan)
    ResolvePlanner.stop(plan_file)
  end

  def preconds_hash(descriptions) when is_list(descriptions) do
    descriptions |> :erlang.term_to_binary() |> :erlang.md5()
  end

  @literals_and_basic [
    quote(context: TwoFieldStruct, do: any()),
    quote(context: TwoFieldStruct, do: atom()),
    quote(context: TwoFieldStruct, do: :an_atom),
    quote(context: TwoFieldStruct, do: true),
    quote(context: TwoFieldStruct, do: false),
    quote(context: TwoFieldStruct, do: nil),
    quote(context: TwoFieldStruct, do: map()),
    quote(context: TwoFieldStruct, do: %{}),
    quote(context: TwoFieldStruct, do: pid()),
    quote(context: TwoFieldStruct, do: port()),
    quote(context: TwoFieldStruct, do: reference()),
    quote(context: TwoFieldStruct, do: tuple()),
    quote(context: TwoFieldStruct, do: float()),
    quote(context: TwoFieldStruct, do: integer()),
    quote(context: TwoFieldStruct, do: 1),
    quote(context: TwoFieldStruct, do: -1),
    quote(context: TwoFieldStruct, do: 1..10),
    quote(context: TwoFieldStruct, do: -10..-1),
    quote(context: TwoFieldStruct, do: neg_integer()),
    quote(context: TwoFieldStruct, do: non_neg_integer()),
    quote(context: TwoFieldStruct, do: pos_integer()),
    quote(context: TwoFieldStruct, do: <<>>),
    quote(context: TwoFieldStruct, do: <<_::9>>),
    quote(context: TwoFieldStruct, do: <<_::_*8>>),
    quote(context: TwoFieldStruct, do: <<_::8, _::_*2>>),
    quote(context: TwoFieldStruct, do: (() -> any())),
    quote(context: TwoFieldStruct, do: (... -> any())),
    quote(context: TwoFieldStruct, do: []),
    quote(context: TwoFieldStruct, do: %NoFieldsStruct{}),
    quote(context: TwoFieldStruct, do: {})
  ]

  def literals_and_basic(), do: @literals_and_basic

  @literals_and_basic_src [
    quote(context: TwoFieldStruct, do: none()),
    quote(context: TwoFieldStruct, do: struct()),
    quote(context: TwoFieldStruct, do: [...])
  ]

  def literals_and_basic_src(), do: @literals_and_basic_src

  @literals_and_basic_dst [
    quote(context: TwoFieldStruct, do: {}),
    quote(context: TwoFieldStruct, do: %{:__struct__ => atom(), optional(atom()) => any()}),
    quote(context: TwoFieldStruct, do: nonempty_list(any()))
  ]

  def literals_and_basic_dst(), do: @literals_and_basic_dst

  @built_in_src [
    quote(context: TwoFieldStruct, do: term()),
    quote(context: TwoFieldStruct, do: arity()),
    quote(context: TwoFieldStruct, do: binary()),
    quote(context: TwoFieldStruct, do: bitstring()),
    quote(context: TwoFieldStruct, do: byte()),
    quote(context: TwoFieldStruct, do: char()),
    quote(context: TwoFieldStruct, do: charlist()),
    quote(context: TwoFieldStruct, do: nonempty_charlist()),
    quote(context: TwoFieldStruct, do: fun()),
    quote(context: TwoFieldStruct, do: function()),
    quote(context: TwoFieldStruct, do: keyword()),
    quote(context: TwoFieldStruct, do: list()),
    quote(context: TwoFieldStruct, do: nonempty_list()),
    quote(context: TwoFieldStruct, do: maybe_improper_list()),
    quote(context: TwoFieldStruct, do: nonempty_maybe_improper_list()),
    quote(context: TwoFieldStruct, do: mfa()),
    quote(context: TwoFieldStruct, do: module()),
    quote(context: TwoFieldStruct, do: no_return()),
    quote(context: TwoFieldStruct, do: node())
  ]

  def built_in_src(), do: @built_in_src

  @built_in_dst [
    quote(context: TwoFieldStruct, do: any()),
    quote(context: TwoFieldStruct, do: 0..255),
    # credo:disable-for-lines:2
    quote(context: TwoFieldStruct, do: <<_::_*8>>),
    quote(context: TwoFieldStruct, do: <<_::_*1>>),
    quote(context: TwoFieldStruct, do: 0..255),
    quote(context: TwoFieldStruct, do: 0..0x10FFFF),
    quote(context: TwoFieldStruct, do: [0..0x10FFFF]),
    quote(context: TwoFieldStruct, do: nonempty_list(0..0x10FFFF)),
    quote(context: TwoFieldStruct, do: (... -> any)),
    quote(context: TwoFieldStruct, do: (... -> any)),
    quote(context: TwoFieldStruct, do: [{atom(), any()}]),
    quote(context: TwoFieldStruct, do: [any()]),
    quote(context: TwoFieldStruct, do: nonempty_list(any())),
    quote(context: TwoFieldStruct, do: maybe_improper_list(any(), any())),
    quote(context: TwoFieldStruct, do: nonempty_maybe_improper_list(any(), any())),
    quote(context: TwoFieldStruct, do: {module(), atom(), 0..255}),
    quote(context: TwoFieldStruct, do: atom()),
    quote(context: TwoFieldStruct, do: {}),
    quote(context: TwoFieldStruct, do: atom())
  ]

  def built_in_dst(), do: @built_in_dst

  @literals_basic_built_in_src @literals_and_basic ++ @literals_and_basic_src ++ @built_in_src

  def literals_basic_built_in_src(), do: @literals_basic_built_in_src

  @literals_basic_built_in_dst @literals_and_basic ++ @literals_and_basic_dst ++ @built_in_dst

  def literals_basic_built_in_dst(), do: @literals_basic_built_in_dst

  def plan_types(types, planner) do
    types
    |> Enum.with_index()
    |> Enum.each(fn {type, idx} ->
      plan(planner, TwoFieldStruct, String.to_atom(to_string(idx)), type)
    end)

    keep_env(planner, TwoFieldStruct, __ENV__)

    flush(planner)
  end

  def env() do
    __ENV__
  end

  def plan(planner, module \\ TwoFieldStruct, field \\ :first, quoted_type) do
    ResolvePlanner.plan_types_resolving(
      planner,
      module,
      field,
      quoted_type
    )
  end

  def plan_struct_integrity_ensurance(planner, module, fields, file, line) do
    ResolvePlanner.plan_struct_integrity_ensurance(
      planner,
      module,
      fields,
      file,
      line
    )
  end

  def keep_global_remote_types_to_treat_as_any(planner, remote_types_as_any) do
    ResolvePlanner.keep_global_remote_types_to_treat_as_any(
      planner,
      remote_types_as_any
    )
  end

  def keep_remote_types_to_treat_as_any(planner, module, remote_types_as_any) do
    ResolvePlanner.keep_remote_types_to_treat_as_any(
      planner,
      module,
      remote_types_as_any
    )
  end

  def plan_precond_checks(planner, module, type_names) do
    ResolvePlanner.plan_precond_checks(planner, module, type_names)
  end

  def keep_env(planner, module \\ TwoFieldStruct, env) do
    ResolvePlanner.keep_module_environment(planner, module, env)
  end

  def flush(planner), do: ResolvePlanner.flush(planner)

  def map_idx_list(list) do
    {list
     |> Enum.map(&add_empty_precond/1)
     |> Enum.with_index()
     |> Enum.map(fn {quoted_type, idx} -> {String.to_atom(to_string(idx)), [quoted_type]} end)
     |> Enum.into(%{}), nil}
  end

  def map_idx_list_multitype(list) do
    {list
     |> Enum.map(fn quoted_types -> Enum.map(quoted_types, &add_empty_precond/1) end)
     |> Enum.with_index()
     |> Enum.map(fn {quoted_precond_types, idx} -> {String.to_atom(to_string(idx)), quoted_precond_types} end)
     |> Enum.into(%{}), nil}
  end

  def add_empty_precond_to_spec(fields) do
    {fields
     |> Enum.map(fn {field, spec_list} -> {field, Enum.map(spec_list, &add_empty_precond/1)} end)
     |> Enum.into(%{}), nil}
  end

  def add_empty_precond([{_key, _value} | _] = kv_list) do
    updated_kv_list = Enum.map(kv_list, fn {key, value} -> {add_empty_precond_key(key), add_empty_precond(value)} end)
    {updated_kv_list, nil}
  end

  def add_empty_precond([{:->, meta, [[_ | _] = args, return_type]}]) do
    updated_args =
      case add_empty_precond(args) do
        {updated_values, _} -> updated_values
        updated_values -> updated_values
      end

    {[{:->, meta, [updated_args, return_type]}], nil}
  end

  def add_empty_precond([{:->, _, _}] = value) do
    {value, nil}
  end

  def add_empty_precond([{:..., _, _}] = value) do
    value
  end

  def add_empty_precond({:.., _, [0, 0x10FFFF]} = value) do
    {value, nil}
  end

  def add_empty_precond({kind, [], []} = value) when kind in [:<<>>, :%{}] do
    value
  end

  def add_empty_precond({list_kind, [], values})
      when list_kind in [:nonempty_list, :nonempty_improper_list, :nonempty_maybe_improper_list, :maybe_improper_list] do
    updated_values =
      case add_empty_precond(values) do
        {updated_values, _} -> updated_values
        updated_values -> updated_values
      end

    {{list_kind, [], updated_values}, nil}
  end

  def add_empty_precond([]) do
    []
  end

  def add_empty_precond([value]) do
    {[add_empty_precond(value)], nil}
  end

  def add_empty_precond([_ | _] = value) do
    Enum.map(value, &add_empty_precond/1)
  end

  def add_empty_precond({:%, [], [struct_alias, {:%{}, [], values}]}) do
    kv_precond =
      case add_empty_precond(values) do
        {kv_precond, _} -> kv_precond
        kv_precond -> kv_precond
      end

    {{:%, [], [struct_alias, {:%{}, [], kv_precond}]}, nil}
  end

  def add_empty_precond({:%{}, [], values}) do
    kv_precond =
      case add_empty_precond(values) do
        {kv_precond, _} -> kv_precond
        kv_precond -> kv_precond
      end

    {{:%{}, [], kv_precond}, nil}
  end

  def add_empty_precond({value1, value2}) do
    {{add_empty_precond(value1), add_empty_precond(value2)}, nil}
  end

  def add_empty_precond({:{}, [], []} = value) do
    value
  end

  def add_empty_precond({:{}, [], values}) do
    updated_values =
      case add_empty_precond(values) do
        {updated_values, _} -> updated_values
        updated_values -> updated_values
      end

    {{:{}, [], updated_values}, nil}
  end

  def add_empty_precond(value) when is_number(value) or is_atom(value) do
    value
  end

  def add_empty_precond({kind, _, _} = value) when kind in [:any, :term, :pid, :port, :reference] do
    value
  end

  def add_empty_precond(value) do
    {value, nil}
  end

  def add_empty_precond_key({field_type, [], [value]}) when field_type in [:required, :optional] do
    {field_type, [], [add_empty_precond(value)]}
  end

  def add_empty_precond_key(key) do
    key
  end

  def read_types(types_file) do
    types_file
    |> File.read!()
    |> :erlang.binary_to_term()
  end

  def read_deps(deps_file) do
    deps_file
    |> File.read!()
    |> :erlang.binary_to_term()
  end
end
