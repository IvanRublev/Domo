defmodule Domo.TypeEnsurerFactory.Resolver.OrTest do
  use Domo.FileCase

  alias Domo.TypeEnsurerFactory.Resolver

  import ResolverTestHelper

  setup [:setup_project_planner]

  describe "TypeEnsurerFactory.Resolver should" do
    test "resolve literals and basic t1 and t2 in t1 | t2", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
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

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected =
        for {arg1, arg2} <-
              Enum.zip(literals_and_basic_dst(), shift_list.(literals_and_basic_dst())) do
          [
            quote(context: TwoFieldStruct, do: unquote(arg1) | unquote(arg2))
          ]
        end

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve operands of multiple |", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [quote(context: TwoFieldStruct, do: module() | integer() | float() | list())],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: atom() | integer() | float() | [any()])
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | to list rejecting rest options for any()", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(context: TwoFieldStruct, do: any() | float()),
          quote(context: TwoFieldStruct, do: atom() | integer() | any() | float()),
          quote(context: TwoFieldStruct, do: atom() | integer() | float() | term())
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [quote(context: TwoFieldStruct, do: any())],
        [quote(context: TwoFieldStruct, do: any())],
        [quote(context: TwoFieldStruct, do: any())]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b in {a | b}", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: {module() | integer(), float() | pid(), port() | atom()}
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(
            context: TwoFieldStruct,
            do: {atom() | integer(), float() | pid(), port() | atom()}
          )
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b with nested tuples {c, {a | b}}", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: 2 | {pid(), port(), module() | {integer() | module(), 1}}
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(
            context: TwoFieldStruct,
            do: 2 | {pid(), port(), atom() | {integer() | atom(), 1}}
          )
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within [a | b]", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: [integer() | module()]
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          [quote(context: TwoFieldStruct, do: integer() | atom())]
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within proper and improper lists (a | b) ", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do:
              list(
                nonempty_list(
                  nonempty_improper_list(1 | module(), 3 | 4)
                  | nonempty_maybe_improper_list(5 | 6, 7 | module())
                )
                | maybe_improper_list([9 | module(), ...], module() | 12)
              )
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          [
            quote(
              context: TwoFieldStruct,
              do:
                nonempty_list(nonempty_improper_list(1 | atom(), 3 | 4) | nonempty_maybe_improper_list(5 | 6, 7 | atom()))
                | maybe_improper_list(nonempty_list(9 | atom()), atom() | 12)
            )
          ]
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within keyword list [key: a | b]", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: [key1: integer() | module()]
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(
            context: TwoFieldStruct,
            do: [{:key1, integer() | atom()}]
          )
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within keyword(a | b)", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: keyword(module() | float()))], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: [{atom(), atom() | float()}])
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within as_boolean(a | b)", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: as_boolean(integer() | module()))], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: integer() | atom())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within map %{ a | b => a | b}", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: TwoFieldStruct,
            do: %{
              key1: %{
                required(module() | integer()) => module() | neg_integer(),
                optional(pid() | module()) => float() | module()
              },
              key2: 1 | 2,
              key3: %{(module() | integer()) => module() | neg_integer()}
            }
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(
            context: TwoFieldStruct,
            do: %{
              key1: %{
                required(atom() | integer()) => atom() | neg_integer(),
                optional(pid() | atom()) => float() | atom()
              },
              key2: 1 | 2,
              key3: %{(atom() | integer()) => atom() | neg_integer()}
            }
          )
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve | within ensurable struct to struct with any fields", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [
          quote(
            context: CustomStructUsingDomo,
            do: %CustomStructUsingDomo{fist: integer() | nil, second: float() | atom()}
          )
        ],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [[quote(context: CustomStructUsingDomo, do: %CustomStructUsingDomo{})]]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve a and b within function(a | b)", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types(
        [quote(context: TwoFieldStruct, do: (module() | pid(), integer() | float() -> any()))],
        planner
      )

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: (atom() | pid(), integer() | float() -> any()))
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve boolean() to list of false and true", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: boolean())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: true | false)
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve identifier() to list of pid, port, reference", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: identifier())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          {
            :|,
            [],
            [
              {:pid, [], []},
              {:|, [],
               [
                 {:reference, [], []},
                 {:port, [], []}
               ]}
            ]
          }
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
           deps_file: deps_file,
           ecto_assocs_file: ecto_assocs_file,
           t_reflections_file: t_reflections_file
         } do
      plan_types([quote(context: TwoFieldStruct, do: iolist())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: maybe_improper_list(0..255 | <<_::_*8>>, <<_::_*8>> | []))
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve iodata() to iolist() or list of binary", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: iodata())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: <<_::_*8>> | maybe_improper_list(0..255 | <<_::_*8>>, <<_::_*8>> | []))
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve number() to list of integer and float", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: number())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: integer() | float())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end

    test "resolve timeout() to list of :infinity and non_neg_integer", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan_types([quote(context: TwoFieldStruct, do: timeout())], planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      expected = [
        [
          quote(context: TwoFieldStruct, do: :infinity | non_neg_integer())
        ]
      ]

      assert %{TwoFieldStruct => map_idx_list_multitype(expected)} == read_types(types_file)
    end
  end
end
