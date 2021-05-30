defmodule Domo.TypeEnsurerFactory.Resolver.OrTest do
  use Domo.FileCase

  alias Domo.TypeEnsurerFactory.Resolver

  import ResolverTestHelper

  setup [:setup_project_planner]

  describe "TypeEnsurerFactory.Resolver should" do
    test "resolve literals and basic t1 | t1 to list [t1, t1]", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      shift_list = fn list ->
        List.delete_at(list, 0) ++ [hd(list)]
      end

      types =
        for {arg1, arg2} <-
              Enum.zip(literals_and_basic_src(), shift_list.(literals_and_basic_src())) do
          quote(context: TwoFieldStruct, do: unquote(arg1) | unquote(arg2))
        end

      plan_types(types, planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected =
        for {arg1, arg2} <-
              Enum.zip(literals_and_basic_dst(), shift_list.(literals_and_basic_dst())) do
          [
            quote(context: TwoFieldStruct, do: unquote(arg1)),
            quote(context: TwoFieldStruct, do: unquote(arg2))
          ]
        end

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve multiple | to list", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [quote(context: TwoFieldStruct, do: atom() | integer() | float() | list())],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: atom()),
          quote(context: TwoFieldStruct, do: integer()),
          quote(context: TwoFieldStruct, do: float()),
          quote(context: TwoFieldStruct, do: [any()])
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | to list rejecting duplicates", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [quote(context: TwoFieldStruct, do: atom() | integer() | atom() | atom())],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: atom()),
          quote(context: TwoFieldStruct, do: integer())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | to list rejecting rest options for any()", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(context: TwoFieldStruct, do: any() | float()),
          quote(context: TwoFieldStruct, do: atom() | integer() | any() | float()),
          quote(context: TwoFieldStruct, do: atom() | integer() | term() | float())
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [quote(context: TwoFieldStruct, do: any())],
        [quote(context: TwoFieldStruct, do: any())],
        [quote(context: TwoFieldStruct, do: any())]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve tuple with multiple | arguments to list of tuples", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: {atom() | integer(), float() | pid(), port() | atom()}
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: {atom(), float(), port()}),
          quote(context: TwoFieldStruct, do: {atom(), float(), atom()}),
          quote(context: TwoFieldStruct, do: {atom(), pid(), port()}),
          quote(context: TwoFieldStruct, do: {atom(), pid(), atom()}),
          quote(context: TwoFieldStruct, do: {integer(), float(), port()}),
          quote(context: TwoFieldStruct, do: {integer(), float(), atom()}),
          quote(context: TwoFieldStruct, do: {integer(), pid(), port()}),
          quote(context: TwoFieldStruct, do: {integer(), pid(), atom()})
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | with nested tuples to list", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: 2 | {pid(), port(), atom() | {integer() | float(), 1}}
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: 2),
          quote(context: TwoFieldStruct, do: {pid(), port(), atom()}),
          quote(context: TwoFieldStruct, do: {pid(), port(), {integer(), 1}}),
          quote(context: TwoFieldStruct, do: {pid(), port(), {float(), 1}})
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within [] to list", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: 2 | [pid() | [integer() | float()]]
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: 2),
          [quote(context: TwoFieldStruct, do: pid())],
          [[quote(context: TwoFieldStruct, do: integer())]],
          [[quote(context: TwoFieldStruct, do: float())]]
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within proper and improper lists to list of lists", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do:
              list(
                nonempty_list(
                  nonempty_improper_list(1 | 2, 3 | 4)
                  | nonempty_maybe_improper_list(5 | 6, 7 | 8)
                )
                | maybe_improper_list([9 | 10, ...], 11 | 12)
              )
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_improper_list(1, 3)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_improper_list(1, 4)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_improper_list(2, 3)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_improper_list(2, 4)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_maybe_improper_list(5, 7)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_maybe_improper_list(5, 8)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_maybe_improper_list(6, 7)))],
          [quote(context: TwoFieldStruct, do: nonempty_list(nonempty_maybe_improper_list(6, 8)))],
          [quote(context: TwoFieldStruct, do: maybe_improper_list(nonempty_list(9), 11))],
          [quote(context: TwoFieldStruct, do: maybe_improper_list(nonempty_list(9), 12))],
          [quote(context: TwoFieldStruct, do: maybe_improper_list(nonempty_list(10), 11))],
          [quote(context: TwoFieldStruct, do: maybe_improper_list(nonempty_list(10), 12))]
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within keyword list to list of lists", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: [{:key1 | :key2, integer() | atom()}]
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: [key1: integer()]),
          quote(context: TwoFieldStruct, do: [key1: atom()]),
          quote(context: TwoFieldStruct, do: [key2: integer()]),
          quote(context: TwoFieldStruct, do: [key2: atom()])
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within keyword(t) to list of keyword lists", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: keyword(integer() | float()))], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: [{atom(), integer()}]),
          quote(context: TwoFieldStruct, do: [{atom(), float()}])
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within as_boolean(t) to list of t", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: as_boolean(integer() | float()))], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: integer()),
          quote(context: TwoFieldStruct, do: float())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within map to list of maps", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: %{
              key1: %{
                required(atom() | integer()) => float() | neg_integer(),
                optional(pid() | port()) => list() | tuple()
              },
              key2: 1 | 2
            }
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(pid()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(pid()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(pid()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(pid()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(port()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(port()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(port()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => float(), optional(port()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(pid()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(pid()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(pid()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(pid()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(port()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(port()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(port()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(atom()) => neg_integer(), optional(port()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(pid()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(pid()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(pid()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(pid()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(port()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(port()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(port()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => float(), optional(port()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(pid()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(pid()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(pid()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(pid()) => tuple()}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(port()) => [any()]}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(port()) => [any()]}, key2: 2}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(port()) => tuple()}, key2: 1}),
          quote(context: TwoFieldStruct, do: %{key1: %{required(integer()) => neg_integer(), optional(port()) => tuple()}, key2: 2})
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within structs to list of structs", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: %TwoFieldStruct{fist: integer() | nil, second: float() | atom()}
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: %TwoFieldStruct{fist: integer(), second: float()}),
          quote(context: TwoFieldStruct, do: %TwoFieldStruct{fist: integer(), second: atom()}),
          quote(context: TwoFieldStruct, do: %TwoFieldStruct{fist: nil, second: float()}),
          quote(context: TwoFieldStruct, do: %TwoFieldStruct{fist: nil, second: atom()})
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within funcion arguments to list of functions", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types(
        [quote(context: TwoFieldStruct, do: (atom() | pid(), integer() | float() -> any()))],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: (atom(), integer() -> any())),
          quote(context: TwoFieldStruct, do: (atom(), float() -> any())),
          quote(context: TwoFieldStruct, do: (pid(), integer() -> any())),
          quote(context: TwoFieldStruct, do: (pid(), float() -> any()))
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve boolean() to list of false and true", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: boolean())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: false),
          quote(context: TwoFieldStruct, do: true)
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve identifier() to list of pid, port, reference", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: identifier())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: pid()),
          quote(context: TwoFieldStruct, do: port()),
          quote(context: TwoFieldStruct, do: reference())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve iolist() to maybe_improper_list(byte() | binary(), binary() | []) TODO: update first argument for recursive iolist",
         %{
           planner: planner,
           plan_file: plan_file,
           preconds_file: preconds_file,
           types_file: types_file,
           deps_file: deps_file
         } do
      plan_types([quote(context: TwoFieldStruct, do: iolist())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: maybe_improper_list(0..255, <<_::_*8>>)),
          quote(context: TwoFieldStruct, do: maybe_improper_list(0..255, [])),
          quote(context: TwoFieldStruct, do: maybe_improper_list(<<_::_*8>>, <<_::_*8>>)),
          quote(context: TwoFieldStruct, do: maybe_improper_list(<<_::_*8>>, []))
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve iodata() to iolist or list of binary", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: iodata())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: <<_::_*8>>),
          quote(context: TwoFieldStruct, do: maybe_improper_list(0..255, <<_::_*8>>)),
          quote(context: TwoFieldStruct, do: maybe_improper_list(0..255, [])),
          quote(context: TwoFieldStruct, do: maybe_improper_list(<<_::_*8>>, <<_::_*8>>)),
          quote(context: TwoFieldStruct, do: maybe_improper_list(<<_::_*8>>, []))
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve number() to list of integer and float", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: number())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: integer()),
          quote(context: TwoFieldStruct, do: float())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve timeout() to list of :infinity and non_neg_integer", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: timeout())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file)

      expected = [
        [
          quote(context: TwoFieldStruct, do: :infinity),
          quote(context: TwoFieldStruct, do: non_neg_integer())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end
  end
end
