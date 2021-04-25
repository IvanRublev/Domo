defmodule ResolverTestHelper do
  @moduledoc false

  alias Mix.Tasks.Compile.DomoCompiler, as: DomoMixTask
  alias Domo.TypeEnsurerFactory.ResolvePlanner

  @project_stub MixProjectStubCorrect

  def setup_project_planner(_context) do
    plan_file = DomoMixTask.manifest_path(@project_stub, :plan)
    types_file = DomoMixTask.manifest_path(@project_stub, :types)
    deps_file = DomoMixTask.manifest_path(@project_stub, :deps)

    stop_project_palnner()

    {:ok, _pid} = ResolvePlanner.start(plan_file)

    ExUnit.Callbacks.on_exit(fn ->
      stop_project_palnner()
    end)

    %{
      planner: plan_file,
      project_stub: @project_stub,
      plan_file: plan_file,
      types_file: types_file,
      deps_file: deps_file
    }
  end

  def stop_project_palnner do
    plan_file = DomoMixTask.manifest_path(@project_stub, :plan)
    ResolvePlanner.stop(plan_file)
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
    quote(context: TwoFieldStruct, do: 1..10),
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

  @spec literals_and_basic :: list()
  def literals_and_basic(), do: @literals_and_basic

  @literals_and_basic_src [
    quote(context: TwoFieldStruct, do: none()),
    quote(context: TwoFieldStruct, do: struct()),
    quote(context: TwoFieldStruct, do: [...])
  ]

  @spec literals_and_basic_src :: list()
  def literals_and_basic_src(), do: @literals_and_basic_src

  @literals_and_basic_dst [
    quote(context: TwoFieldStruct, do: {}),
    quote(
      context: TwoFieldStruct,
      do: %{:__struct__ => atom(), optional(atom()) => any()}
    ),
    quote(context: TwoFieldStruct, do: nonempty_list(any()))
  ]

  @spec literals_and_basic_dst :: list()
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

  @spec built_in_src :: list()
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

  @spec built_in_dst :: list()
  def built_in_dst(), do: @built_in_dst

  @literals_basic_built_in_src @literals_and_basic ++ @literals_and_basic_src ++ @built_in_src

  @spec literals_basic_built_in_src :: list()
  def literals_basic_built_in_src(), do: @literals_basic_built_in_src

  @literals_basic_built_in_dst @literals_and_basic ++ @literals_and_basic_dst ++ @built_in_dst

  @spec literals_basic_built_in_dst :: list()
  def literals_basic_built_in_dst(), do: @literals_basic_built_in_dst

  @spec plan_types(list(), pid) :: :ok
  def plan_types(types, planner) do
    types
    |> Enum.with_index()
    |> Enum.each(fn {type, idx} ->
      plan(planner, TwoFieldStruct, String.to_atom(to_string(idx)), type)
    end)

    keep_env(planner, TwoFieldStruct, __ENV__)

    flush(planner)
  end

  @spec plan(pid, module, atom, Macro.t()) :: :ok
  def plan(planner, module \\ TwoFieldStruct, field \\ :first, quoted_type) do
    ResolvePlanner.plan_types_resolving(
      planner,
      module,
      field,
      quoted_type
    )
  end

  @spec keep_env(pid, module, Macro.env()) :: :ok
  def keep_env(planner, module \\ TwoFieldStruct, env) do
    ResolvePlanner.keep_module_environment(planner, module, env)
  end

  @spec flush(pid) :: :ok
  def flush(planner), do: ResolvePlanner.flush(planner)

  @spec map_idx_list([Macro.t()]) :: %{required(atom) => [Macro.t()]}
  def map_idx_list(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {quoted_type, idx} ->
      {String.to_atom(to_string(idx)), [quoted_type]}
    end)
    |> Enum.into(%{})
  end

  @spec map_idx_list_multitype([Macro.t()]) :: %{required(atom) => [Macro.t()]}
  def map_idx_list_multitype(list) do
    list
    |> Enum.with_index()
    |> Enum.map(fn {quoted_types, idx} ->
      {String.to_atom(to_string(idx)), quoted_types}
    end)
    |> Enum.into(%{})
  end

  @spec read_types(String.t()) :: map()
  def read_types(types_file) do
    types_file
    |> File.read!()
    |> :erlang.binary_to_term()
  end

  @spec read_deps(String.t()) :: map()
  def read_deps(deps_file) do
    deps_file
    |> File.read!()
    |> :erlang.binary_to_term()
  end
end
