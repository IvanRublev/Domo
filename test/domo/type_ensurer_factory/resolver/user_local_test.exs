defmodule Domo.TypeEnsurerFactory.Resolver.UserLocalTest do
  use Domo.FileCase

  alias Domo.TypeEnsurerFactory.Resolver

  import ResolverTestHelper

  setup [:setup_project_planner]

  describe "TypeEnsurerFactory.Resolver should" do
    test "resolve user type to primitive type recursively traveling local types", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(planner, LocalUserType, :field, quote(context: LocalUserType, do: indirect_int()))
      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      assert %{
               LocalUserType =>
                 add_empty_precond_to_spec(%{
                   field: [quote(context: LocalUserType, do: integer())]
                 })
             } == read_types(types_file)
    end

    test "resolve user type that is a list and it's element remote types recursively", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(
        planner,
        LocalUserType,
        :remote_field,
        quote(context: LocalUserType, do: list_remote_user_type())
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      assert %{
               LocalUserType =>
                 add_empty_precond_to_spec(%{
                   remote_field: [quote(context: LocalUserType, do: [float()])]
                 })
             } == read_types(types_file)
    end

    test "resolve user type that is a tuple having element types defined with variables", %{
      planner: planner,
      plan_file: plan_file,
      preconds_file: preconds_file,
      types_file: types_file,
      deps_file: deps_file
    } do
      plan(
        planner,
        LocalUserType,
        :remote_field,
        quote(context: LocalUserType, do: remote_tuple_vars())
      )

      keep_env(planner, LocalUserType, LocalUserType.env())
      flush(planner)

      :ok = Resolver.resolve(plan_file, preconds_file, types_file, deps_file, false)

      assert %{
               LocalUserType => {
                 %{remote_field: [{{:{}, [], [{{:float, [], []}, nil}, {{:integer, [], []}, nil}]}, nil}]},
                 nil
               }
             } ==
               read_types(types_file)
    end
  end
end
