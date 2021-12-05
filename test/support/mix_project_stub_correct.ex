defmodule MixProjectStubCorrect do
  @moduledoc false

  import PathHelpers

  def config, do: [compilers: [:domo_compiler, :elixir]]

  def build_path, do: tmp_path()
end
