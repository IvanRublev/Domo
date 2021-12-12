defmodule Benchmark.MixProject do
  use Mix.Project

  def project do
    [
      app: :benchmark,
      version: "0.1.0",
      elixir: "~> 1.11",
      compilers: compilers(),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def compilers do
    [:domo_compiler] ++ Mix.compilers()
  end

  # Run "mix benchmark" to do benchmark.
  def aliases do
    [
      benchmark: "run -e 'Benchmark.run()'"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:domo, path: ".."},
      {:benchee, "~> 1.0", runtime: false},
      {:stream_data, "~> 0.5.0", runtime: false},
      {:profiler, "~> 0.1.0", runtime: false}
    ]
  end
end
