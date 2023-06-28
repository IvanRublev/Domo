defmodule Domo.CodeEvaluationTest do
  use Domo.FileCase, async: false
  use Placebo

  alias Domo.CodeEvaluation
  alias Domo.MixProject

  @answer_holder_source """
  defmodule AnswerBaker do
    defmacro __before_compile__(_env) do
      value = Domo.CodeEvaluation.in_mix_compile?()

      quote do
        def in_mix_compile_return_value, do: unquote(value)
      end
    end
  end

  defmodule AnswerHolder do
    @before_compile AnswerBaker
  end
  """

  describe "in_mix_compile?" do
    test "returns true executed with `mix compile` command" do
      path = MixProject.out_of_project_tmp_path("/raising_on_mix_compile.ex")

      File.write!(path, @answer_holder_source)

      CompilerHelpers.compile_with_elixir()
      assert apply(AnswerHolder, :in_mix_compile_return_value, []) == true
    end

    test "returns false executed in iex/test environment" do
      Code.eval_string(@answer_holder_source)

      assert apply(AnswerHolder, :in_mix_compile_return_value, []) == false
    end
  end

  describe "in_mix_test?" do
    test "returns true when executed with `mix test` command" do
      assert CodeEvaluation.in_mix_test?() == true
    end

    test "returns false when executed Not with `mix test`" do
      allow GenServer.whereis(ExUnit.Server), meck_options: [:passthrough], return: nil
      assert CodeEvaluation.in_mix_test?() == false
    end
  end

  test "put_plan_collection/1, in_plan_collection?/0 keep flag in application settings" do
    assert CodeEvaluation.in_plan_collection?() == false

    CodeEvaluation.put_plan_collection(true)
    assert CodeEvaluation.in_plan_collection?() == true

    CodeEvaluation.put_plan_collection(false)
    assert CodeEvaluation.in_plan_collection?() == false
  end
end
