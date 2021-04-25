# credo:disable-for-this-file
defmodule MixProjectStubEmpty do
  def config, do: []
end

defmodule MixProjectStubWrongCompilersOrder do
  def config, do: [compilers: [:domo_compiler, :elixir]]
end

defmodule MixProjectStubCorrect do
  import PathHelpers

  def config, do: [compilers: [:elixir, :domo_compiler]]

  def build_path, do: tmp_path()
end
