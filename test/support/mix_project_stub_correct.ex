defmodule MixProjectStubCorrect do
  @moduledoc false

  import PathHelpers

  def config, do: [compilers: [:domo_compiler, :elixir]]

  def manifest_path, do: tmp_path()

  def get, do: Domo.MixProject
end
