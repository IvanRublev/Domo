defmodule Domo.TypeEnsurerFactory.Resolver.BasicsTest do
  use Domo.FileCase
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Resolver

  import ResolverTestHelper
  import GeneratorTestHelper

  setup [:setup_project_planner]

  setup do
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true
    :ok
  end

  defmodule FailingFile do
    def write(_path, _content), do: {:error, :write_error}
  end

  describe "TypeEnsurerFactory.Resolver should" do
    test "return the error if no plan file is found", %{
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: ^plan_file,
                  struct_module: nil,
                  message: :no_plan
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)
    end

    test "return error when there is no environment for the struct's module in the plan file", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan(planner, LocalUserType, :field, quote(context: LocalUserType, do: int()))
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: ^plan_file,
                  struct_module: LocalUserType,
                  message: :no_env_in_plan
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)
    end

    test "return :ok when there is environment for struct's module in plan file", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan(planner, LocalUserType, :field, quote(context: LocalUserType, do: int()))
      keep_env(planner, LocalUserType, __ENV__)
      flush(planner)

      assert :ok == Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)
    end

    test "write types file and return :ok when all types from plan file are resolved", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan_types([quote(do: integer)], planner)

      assert :ok == Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)
      assert true == File.exists?(types_file)
    end

    test "return error if can't write types file", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan(planner, quote(do: integer))
      keep_env(planner, __ENV__)
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: ^types_file,
                  struct_module: nil,
                  message: {:types_manifest_failed, :write_error}
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, FailingFile, false)
    end

    test "return error encouraging to use domo for struct not using it yet", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan_types(
        [
          quote(
            context: CustomStruct,
            do: %CustomStruct{fist: integer() | nil, second: float() | atom()}
          )
        ],
        planner
      )

      assert {:error, [message]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      assert %Error{
               compiler_module: Resolver,
               message: "Consider to use Domo in CustomStruct struct for validation speed." <> _,
               struct_module: TwoFieldStruct
             } = message
    end

    test "write all types for all modules from the plan to a types file", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(do: integer()))
      plan(planner, AllDefaultsStruct, :first, quote(do: integer()))
      plan(planner, AllDefaultsStruct, :second, quote(do: float()))
      keep_env(planner, TwoFieldStruct, __ENV__)
      keep_env(planner, AllDefaultsStruct, __ENV__)
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      assert %{
               TwoFieldStruct =>
               types_content_empty_precond(%{
                   first: [quote(do: integer())]
                 }),
               AllDefaultsStruct =>
               types_content_empty_precond(%{
                   first: [quote(do: integer())],
                   second: [quote(do: float())]
                 })
             } == read_types(types_file)
    end

    test "write Ecto.Schema types to a types file", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(do: Ecto.Schema.has_many(atom())))
      keep_env(planner, TwoFieldStruct, __ENV__)
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      assert %{TwoFieldStruct => [:first]} == read_ecto_assocs(ecto_assocs_file)
    end

    test "keep literals and basic types as is", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan_types(literals_and_basic(), planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      assert %{TwoFieldStruct => map_idx_list(literals_and_basic())} ==
               read_types(types_file)
    end

    test "drops line metadata for literals and basic types kept as is", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      typespec_with_metadata =
        Enum.map(literals_and_basic(), fn
          {typespec, [], []} -> {typespec, [line: 0], []}
          typespec -> typespec
        end)

      plan_types(typespec_with_metadata, planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      assert %{TwoFieldStruct => map_idx_list(literals_and_basic())} ==
               read_types(types_file)
    end

    test "map built-in and literals types to literals and basic types", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan_types(literals_and_basic_src() ++ built_in_src(), planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      assert %{TwoFieldStruct => map_idx_list(literals_and_basic_dst() ++ built_in_dst())} ==
               read_types(types_file)
    end

    test "map Enum.t() to any()", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: Enum.t())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

      expected = [[{:any, [], []}]]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    ExUnit.Case.register_attribute(__ENV__, :src_dst_types)

    for {type, generator} <- [
          {"function",
           &[
             quote(context: TwoFieldStruct, do: (unquote(&1) -> unquote({:any, [], []}))),
             quote(context: TwoFieldStruct, do: (unquote(&1), unquote(&1) -> unquote({:any, [], []}))),
             quote(context: TwoFieldStruct, do: (unquote(&1), unquote(&1), unquote(&1) -> unquote({:any, [], []})))
           ]},
          {"map with atom keys",
           &[
             quote(context: TwoFieldStruct, do: %{key: unquote(&1)}),
             quote(context: TwoFieldStruct, do: %{key: unquote(&1), key1: unquote(&1)})
           ]},
          {"map",
           &[
             quote(context: TwoFieldStruct, do: %{required(unquote(&1)) => unquote(&1)}),
             quote(context: TwoFieldStruct, do: %{optional(unquote(&1)) => unquote(&1)}),
             quote(
               context: TwoFieldStruct,
               do: %{
                 required(atom()) => unquote(&1),
                 optional(unquote(&1)) => atom()
               }
             ),
             quote(
               context: TwoFieldStruct,
               do: %{
                 required(unquote(&1)) => unquote(&1),
                 required(unquote(&1)) => atom(),
                 optional(integer()) => unquote(&1)
               }
             )
           ]},
          {"tuple",
           &[
             quote(context: TwoFieldStruct, do: {unquote(&1)}),
             quote(context: TwoFieldStruct, do: {unquote(&1), unquote(&1)}),
             quote(context: TwoFieldStruct, do: {unquote(&1), unquote(&1), unquote(&1)})
           ]},
          {"keyword list",
           &[
             quote(context: TwoFieldStruct, do: [key: unquote(&1)]),
             quote(context: TwoFieldStruct, do: [key: unquote(&1), key1: unquote(&1)])
           ]},
          {"proper and improper lists",
           &[
             quote(context: TwoFieldStruct, do: [unquote(&1)]),
             quote(context: TwoFieldStruct, do: nonempty_list(unquote(&1))),
             quote(context: TwoFieldStruct, do: maybe_improper_list(unquote(&1), unquote(&1))),
             quote(context: TwoFieldStruct, do: nonempty_improper_list(unquote(&1), unquote(&1))),
             quote(
               context: TwoFieldStruct,
               do: nonempty_maybe_improper_list(unquote(&1), unquote(&1))
             )
           ]}
        ] do
      compose_types = fn simple_types ->
        simple_types
        |> Enum.map(&generator.(&1))
        |> Enum.flat_map(& &1)
      end

      @src_dst_types {compose_types.(literals_basic_built_in_src()), compose_types.(literals_basic_built_in_dst())}

      test "resolve literal, basic, and built-in type arguments for #{type} appropriately", %{
        planner: planner,
        plan_file: plan_file,
        preconds_file: preconds_file,
        types_file: types_file,
        deps_file: deps_file,
        ecto_assocs_file: ecto_assocs_file,
        registered: registered
      } do
        {src_types, dst_types} = registered.src_dst_types

        plan_types(src_types, planner)

        :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

        assert %{TwoFieldStruct => map_idx_list(dst_types)} == read_types(types_file)
      end
    end
  end

  test "fail to resolve a keyword list type spec with non atom keys", %{
    planner: planner,
    plan_file: plan_file,
    preconds_file: preconds_file,
    types_file: types_file,
    deps_file: deps_file,
    ecto_assocs_file: ecto_assocs_file
  } do
    plan(planner, CustomStruct, :title, quote(do: [{:first, :atom}, {1, integer()}]))
    keep_env(planner, CustomStruct, CustomStruct.env())
    flush(planner)

    module_file = CustomStruct.env().file

    assert {:error,
            [
              %Error{
                compiler_module: Resolver,
                file: ^module_file,
                struct_module: CustomStruct,
                message: :keyword_list_should_has_atom_keys
              }
            ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)
  end

  test "resolve a keyword list type spec", %{
    planner: planner,
    plan_file: plan_file,
    preconds_file: preconds_file,
    types_file: types_file,
    deps_file: deps_file,
    ecto_assocs_file: ecto_assocs_file
  } do
    plan(planner, TwoFieldStruct, :first, quote(do: [first: :atom, second: integer()]))
    keep_env(planner, TwoFieldStruct, __ENV__)
    flush(planner)

    assert :ok == Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)
  end

  test "resolve keyword(t) built-in type to [{any(), appropriate t}]", %{
    planner: planner,
    plan_file: plan_file,
    preconds_file: preconds_file,
    types_file: types_file,
    deps_file: deps_file,
    ecto_assocs_file: ecto_assocs_file
  } do
    types =
      for arg1 <- literals_basic_built_in_src() do
        quote(context: TwoFieldStruct, do: keyword(unquote(arg1)))
      end

    plan_types(types, planner)

    :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

    expected =
      for arg1 <- literals_basic_built_in_dst() do
        quote(context: TwoFieldStruct, do: [{atom(), unquote(arg1)}])
      end

    assert %{TwoFieldStruct => map_idx_list(expected)} == read_types(types_file)
  end

  test "resolve as_boolean(t) built-in type to appropriate t", %{
    planner: planner,
    plan_file: plan_file,
    preconds_file: preconds_file,
    types_file: types_file,
    deps_file: deps_file,
    ecto_assocs_file: ecto_assocs_file
  } do
    types =
      for arg1 <- literals_basic_built_in_src() do
        quote(context: TwoFieldStruct, do: as_boolean(unquote(arg1)))
      end

    plan_types(types, planner)

    :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

    expected =
      for arg1 <- literals_basic_built_in_dst() do
        quote(context: TwoFieldStruct, do: unquote(arg1))
      end

    assert %{TwoFieldStruct => map_idx_list(expected)} == read_types(types_file)
  end

  test "resolve [t, ...] literal to nonempty_list(appropriate t)", %{
    planner: planner,
    plan_file: plan_file,
    preconds_file: preconds_file,
    types_file: types_file,
    deps_file: deps_file,
    ecto_assocs_file: ecto_assocs_file
  } do
    types =
      for arg1 <- literals_basic_built_in_src() do
        quote(context: TwoFieldStruct, do: [unquote(arg1), ...])
      end

    plan_types(types, planner)

    :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

    expected =
      for arg1 <- literals_basic_built_in_dst() do
        quote(context: TwoFieldStruct, do: nonempty_list(unquote(arg1)))
      end

    assert %{TwoFieldStruct => map_idx_list(expected)} == read_types(types_file)
  end

  test "resolve list(t) basic type to [appropriate t]", %{
    planner: planner,
    plan_file: plan_file,
    preconds_file: preconds_file,
    types_file: types_file,
    deps_file: deps_file,
    ecto_assocs_file: ecto_assocs_file
  } do
    types =
      for arg1 <- literals_basic_built_in_src() do
        quote(context: TwoFieldStruct, do: list(unquote(arg1)))
      end

    plan_types(types, planner)

    :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, false)

    expected =
      for arg1 <- literals_basic_built_in_dst() do
        quote(context: TwoFieldStruct, do: [unquote(arg1)])
      end

    assert %{TwoFieldStruct => map_idx_list(expected)} == read_types(types_file)
  end
end
