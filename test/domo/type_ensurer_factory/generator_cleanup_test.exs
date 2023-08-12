defmodule Domo.TypeEnsurerFactory.GeneratorCleanupTest do
  use Domo.FileCase
  use Placebo

  alias Domo.TypeEnsurerFactory.Generator
  alias Domo.TypeEnsurerFactory.Generator.MatchFunRegistry
  import GeneratorTestHelper

  test "Generator should free resource by stopping MatchFunRegistry server after TypeEnsurer module generation" do
    me = self()

    allow MatchFunRegistry.start_link(),
      meck_options: [:passthrough],
      exec: fn ->
        result = :meck.passthrough([])
        send(me, {:registry_start, result})
        result
      end

    allow MatchFunRegistry.stop(any()),
      meck_options: [:passthrough],
      exec: fn pid ->
        :meck.passthrough([pid])
      end

    Generator.generate_one(Elixir, types_content_empty_precond(%{first: [quote(do: integer())]}), [], nil)

    assert_received {:registry_start, {:ok, registry_pid}}
    assert_called MatchFunRegistry.stop(registry_pid)
    assert Process.alive?(registry_pid) == false
  end
end
