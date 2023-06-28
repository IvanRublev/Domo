defmodule Domo.FileCase do
  @moduledoc false
  use ExUnit.CaseTemplate
  alias Domo.MixProject

  setup_all do
    CompilerHelpers.setup_compiler_options()
    ResolverTestHelper.disable_raise_in_test_env()

    on_exit(fn ->
      CompilerHelpers.reset_compiler_options()
      ResolverTestHelper.enable_raise_in_test_env()
    end)
  end

  setup do
    File.mkdir_p!(MixProject.out_of_project_tmp_path())

    on_exit(fn ->
      # to be sure to stop in case of crashes of the production code under test
      ResolverTestHelper.stop_project_palnner()
      File.rm_rf(MixProject.out_of_project_tmp_path())
    end)

    :ok
  end
end
