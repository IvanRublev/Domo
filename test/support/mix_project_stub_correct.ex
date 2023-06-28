defmodule MixProjectStubCorrect do
  @moduledoc false

  alias Domo.MixProject

  def config, do: [compilers: [:domo_compiler, :elixir]]

  def manifest_path, do: MixProject.out_of_project_tmp_path()

  def get, do: MixProject
end
