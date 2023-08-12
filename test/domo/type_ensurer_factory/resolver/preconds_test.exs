defmodule Domo.TypeEnsurerFactory.Resolver.PrecondsTest do[]
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.TermSerializer
  alias Domo.TypeEnsurerFactory.Precondition
  alias Domo.TypeEnsurerFactory.Error
  alias Domo.TypeEnsurerFactory.Resolver

  import ResolverTestHelper

  setup [:setup_project_planner]

  setup do
    allow CodeEvaluation.in_mix_compile?(), meck_options: [:passthrough], return: true
    :ok
  end

  describe "Resolver should" do
    test "return the error if no preconds file is found", %{
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      File.write!(plan_file, TermSerializer.term_to_binary(%{filed_types_to_resolve: nil, environments: nil, remote_types_as_any_by_module: nil, t_reflections: nil}))

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: ^preconds_file,
                  struct_module: nil,
                  message: :no_preconds
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
    end

    test "register preconditions for struct's t type", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(do: %Recipient{field: atom()}))
      keep_env(planner, TwoFieldStruct, __ENV__)
      keep_env(planner, Recipient, __ENV__)
      plan_precond_checks(planner, TwoFieldStruct, t: "func_body1")
      plan_precond_checks(planner, Recipient, t: "func_body2")
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      assert %{
               TwoFieldStruct => {
                 %{
                   first: [
                     {
                       quote(do: %Recipient{}),
                       Precondition.new(module: Recipient, type_name: :t, description: "func_body2")
                     }
                   ]
                 },
                 Precondition.new(module: TwoFieldStruct, type_name: :t, description: "func_body1")
               }
             } == read_types(types_file)
    end

    test "return error for or type precondition", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(context: UserTypes, do: UserTypes.various_type()))
      keep_env(planner, TwoFieldStruct, __ENV__)
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, various_type: "func_body")
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: TwoFieldStruct,
                  message: """
                  Precondition for value of | or type is not allowed. \
                  You can extract each element \
                  of atom() | integer() | float() | list() type to @type \
                  definitions and set precond for each of it.\
                  """
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
    end

    test "register precondition for map type having an or typed field", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(context: TwoFieldStruct, do: UserTypes.map_field_or_typed()))
      keep_env(planner, TwoFieldStruct, __ENV__)
      plan_precond_checks(planner, UserTypes, map_field_or_typed: "func_body")
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      precond = Precondition.new(module: UserTypes, type_name: :map_field_or_typed, description: "func_body")

      assert %{
               TwoFieldStruct => {
                 %{
                   first: [
                     {quote(do: %{key1: 1}), precond},
                     {quote(do: %{key1: :none}), precond}
                   ]
                 },
                 nil
               }
             } == read_types(types_file)
    end

    test "register precondition for remote types in optional key and value of map", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(
        planner,
        TwoFieldStruct,
        :first,
        quote(
          context: UserTypes,
          do: %{
            required(atom()) => UserTypes.some_numbers(),
            optional(UserTypes.strings()) => UserTypes.two_elem_tuple()
          }
        )
      )

      keep_env(planner, TwoFieldStruct, __ENV__)
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, numbers: "func_body1", strings: "func_body2", two_elem_tuple: "func_body3")
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      numbers_precond = Precondition.new(module: UserTypes, type_name: :numbers, description: "func_body1")
      strings_precond = Precondition.new(module: UserTypes, type_name: :strings, description: "func_body2")
      two_elem_tuple_precond = Precondition.new(module: UserTypes, type_name: :two_elem_tuple, description: "func_body3")

      # interesting enough that remote two element tuple is represented in general form for tuples instead of keeping as is.
      atom_list_tuple = {:{}, [], [quote(do: {atom(), nil}), quote(do: {[unquote({:any, [], []})], nil})]}

      assert %{
               TwoFieldStruct => {
                 %{
                   first: [
                     {
                       quote(
                         context: String,
                         do: %{
                           required({atom(), nil}) => {integer(), unquote(numbers_precond)},
                           optional({<<_::_*8>>, unquote(strings_precond)}) => {unquote(atom_list_tuple), unquote(two_elem_tuple_precond)}
                         }
                       ),
                       nil
                     },
                     {
                       quote(
                         context: String,
                         do: %{
                           required({atom(), nil}) => {float(), unquote(numbers_precond)},
                           optional({<<_::_*8>>, unquote(strings_precond)}) => {unquote(atom_list_tuple), unquote(two_elem_tuple_precond)}
                         }
                       ),
                       nil
                     }
                   ]
                 },
                 nil
               }
             } == read_types(types_file)
    end

    test "return precondition conflict error for remote types referring each other", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(context: UserTypes, do: UserTypes.remote_mn_float()))
      plan(planner, TwoFieldStruct, :second, quote(context: UserTypes, do: UserTypes.remote_type()))
      keep_env(planner, TwoFieldStruct, __ENV__)
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, remote_mn_float: "func_body1", remote_type: "func_body2")
      plan_precond_checks(planner, ModuleNested, mn_float: "func_body2")
      plan_precond_checks(planner, RemoteUserType, t: "func_body3")
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: TwoFieldStruct,
                  message: """
                  Precondition conflict for types UserTypes.remote_type() and RemoteUserType.t() \
                  referring one another. You can define only one precondition for either type.\
                  """
                },
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: TwoFieldStruct,
                  message: """
                  Precondition conflict for types UserTypes.remote_mn_float() and ModuleNested.mn_float() \
                  referring one another. You can define only one precondition for either type.\
                  """
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
    end

    test "return precondition conflict error for preconditions of two types referring each other in remote module", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, TwoFieldStruct, :first, quote(context: UserTypes, do: UserTypes.some_numbers()))
      keep_env(planner, TwoFieldStruct, __ENV__)
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, some_numbers: "func_body1", numbers: "func_body2")
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: TwoFieldStruct,
                  message: """
                  Precondition conflict for types UserTypes.some_numbers() and UserTypes.numbers() \
                  referring one another. You can define only one precondition for either type.\
                  """
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
    end

    test "register precondition for local type", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :first, quote(context: UserTypes, do: some_numbers()))
      plan(planner, UserTypes, :second, quote(context: UserTypes, do: map_field_or_typed()))
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, numbers: "func_body1", map_field_or_typed: "func_body2")
      flush(planner)

      assert :ok == Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      precond1 = Precondition.new(module: UserTypes, type_name: :numbers, description: "func_body1")
      precond2 = Precondition.new(module: UserTypes, type_name: :map_field_or_typed, description: "func_body2")

      assert %{
               UserTypes => {
                 %{
                   first: [
                     {quote(do: integer()), precond1},
                     {quote(do: float()), precond1}
                   ],
                   second: [
                     {quote(do: %{key1: 1}), precond2},
                     {quote(do: %{key1: :none}), precond2}
                   ]
                 },
                 nil
               }
             } == read_types(types_file)
    end

    test "return precondition conflict error for preconditions of two local types referring each other", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :first, quote(context: UserTypes, do: some_numbers()))
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, some_numbers: "func_body1", numbers: "func_body2")
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: UserTypes,
                  message: """
                  Precondition conflict for types UserTypes.some_numbers() and UserTypes.numbers() \
                  referring one another. You can define only one precondition for either type.\
                  """
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
    end

    test "return precondition is not supported error for keyword(t) and as_boolean(t)", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :first, quote(context: UserTypes, do: atom_keyword()))
      plan(planner, UserTypes, :second, quote(context: UserTypes, do: atom_as_boolean()))
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, atom_keyword: "func_body1", atom_as_boolean: "func_body2")
      flush(planner)

      assert {:error,
              [
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: UserTypes,
                  message: """
                  Precondition for value of as_boolean(t) type is not allowed. \
                  You can extract t as a user @type and define precondition for it.\
                  """
                },
                %Error{
                  compiler_module: Resolver,
                  file: _,
                  struct_module: UserTypes,
                  message: """
                  Precondition for value of keyword(t) type is not allowed. \
                  You can extract t as a user @type and define precondition for it.\
                  """
                }
              ]} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
    end

    test "return precondition is not supported error for complicated types", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :first, quote(context: UserTypes, do: a_timeout()))
      plan(planner, UserTypes, :second, quote(context: UserTypes, do: an_iolist()))
      plan(planner, UserTypes, :third, quote(context: UserTypes, do: an_iodata()))
      plan(planner, UserTypes, :fourth, quote(context: UserTypes, do: an_identifier()))

      keep_env(planner, UserTypes, UserTypes.env())

      plan_precond_checks(planner, UserTypes,
        a_timeout: "func_body1",
        an_iolist: "func_body2",
        an_iodata: "func_body3",
        an_identifier: "func_body4"
      )

      flush(planner)

      assert {:error, list} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
      assert [
        %Error{struct_module: UserTypes, message: "Precondition for value of identifier() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of iodata() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of iolist() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of timeout() type is not allowed."}
      ] = Enum.sort(list)
    end

    test "return precondition is not supported error for Ecto.Schema types", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :first, quote(context: UserTypes, do: has_one_atom()))
      plan(planner, UserTypes, :second, quote(context: UserTypes, do: embeds_one_atom()))
      plan(planner, UserTypes, :third, quote(context: UserTypes, do: belongs_to_atom()))
      plan(planner, UserTypes, :fourth, quote(context: UserTypes, do: has_many_atom()))
      plan(planner, UserTypes, :fifth, quote(context: UserTypes, do: many_to_many_atom()))
      plan(planner, UserTypes, :sixth, quote(context: UserTypes, do: embeds_many_atom()))

      keep_env(planner, UserTypes, UserTypes.env())

      plan_precond_checks(planner, UserTypes,
        has_one_atom: "func_body1",
        embeds_one_atom: "func_body1",
        belongs_to_atom: "func_body1",
        has_many_atom: "func_body1",
        many_to_many_atom: "func_body1",
        embeds_many_atom: "func_body1"
      )

      flush(planner)

      assert {:error, list} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
      assert [
        %Error{struct_module: UserTypes, message: "Precondition for value of Ecto.Schema.belongs_to(t) type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of Ecto.Schema.embeds_many(t) type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of Ecto.Schema.embeds_one(t) type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of Ecto.Schema.has_many(t) type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of Ecto.Schema.has_one(t) type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of Ecto.Schema.many_to_many(t) type is not allowed."},
      ] = Enum.sort(list)
    end

    test "return precondition is not supported error for primitive types", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :field1, quote(context: UserTypes, do: an_any()))
      plan(planner, UserTypes, :field2, quote(context: UserTypes, do: a_term()))
      plan(planner, UserTypes, :field3, quote(context: UserTypes, do: number_one()))
      plan(planner, UserTypes, :field4, quote(context: UserTypes, do: atom_hello()))
      plan(planner, UserTypes, :field5, quote(context: UserTypes, do: a_boolean()))
      plan(planner, UserTypes, :field6, quote(context: UserTypes, do: empty_list()))
      plan(planner, UserTypes, :field7, quote(context: UserTypes, do: empty_bitstring()))
      plan(planner, UserTypes, :field8, quote(context: UserTypes, do: empty_tuple()))
      plan(planner, UserTypes, :field9, quote(context: UserTypes, do: empty_map()))
      plan(planner, UserTypes, :field10, quote(context: UserTypes, do: a_none()))
      plan(planner, UserTypes, :field11, quote(context: UserTypes, do: a_noreturn()))
      plan(planner, UserTypes, :field12, quote(context: UserTypes, do: a_pid()))
      plan(planner, UserTypes, :field13, quote(context: UserTypes, do: a_port()))
      plan(planner, UserTypes, :field14, quote(context: UserTypes, do: a_reference()))

      keep_env(planner, UserTypes, UserTypes.env())

      plan_precond_checks(planner, UserTypes,
        number_one: "func_body",
        atom_hello: "func_body",
        a_boolean: "func_body",
        empty_list: "func_body",
        empty_bitstring: "func_body",
        empty_tuple: "func_body",
        empty_map: "func_body",
        a_none: "func_body",
        a_noreturn: "func_body",
        a_pid: "func_body",
        a_port: "func_body",
        a_reference: "func_body"
      )

      flush(planner)

      assert {:error, list} = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)
      assert [
        %Error{struct_module: UserTypes, message: "Precondition for value of %{} type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of 1 type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of :hello type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of <<>> type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of [] type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of boolean() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of no_return() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of none() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of pid() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of port() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of reference() type is not allowed."},
        %Error{struct_module: UserTypes, message: "Precondition for value of {} type is not allowed."}
      ] = Enum.sort(list)
    end

    test "register precondition for any/term type", %{
      planner: planner,
      plan_file: plan_file,
      types_file: types_file,
      preconds_file: preconds_file,
      deps_file: deps_file,
      ecto_assocs_file: ecto_assocs_file,
      t_reflections_file: t_reflections_file
    } do
      plan(planner, UserTypes, :field1, quote(context: UserTypes, do: an_any()))
      plan(planner, UserTypes, :field2, quote(context: UserTypes, do: a_term()))
      keep_env(planner, UserTypes, UserTypes.env())
      plan_precond_checks(planner, UserTypes, an_any: "func_body1", a_term: "func_body2")
      flush(planner)

      assert :ok == Resolver.resolve(plan_file, preconds_file, types_file, deps_file, ecto_assocs_file, t_reflections_file, false)

      precond1 = Precondition.new(module: UserTypes, type_name: :an_any, description: "func_body1")
      precond2 = Precondition.new(module: UserTypes, type_name: :a_term, description: "func_body2")

      assert %{
               UserTypes => {
                 %{
                   field1: [{quote(do: unquote({:any, [], []})), precond1}],
                   field2: [{quote(do: unquote({:any, [], []})), precond2}]
                 },
                 nil
               }
             } == read_types(types_file)
    end
  end
end
