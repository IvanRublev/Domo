# credo:disable-for-this-file
defmodule MixProjectStubEmpty do
  def config, do: []
end

defmodule MixProjectStubWrongCompilersOrder do
  def config, do: [compilers: [:domo, :elixir]]
end

defmodule MixProjectStubCorrect do
  import PathHelpers

  def config, do: [compilers: [:elixir, :domo]]

  def build_path, do: tmp_path()
end
