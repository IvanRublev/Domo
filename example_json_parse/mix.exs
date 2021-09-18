defmodule ExampleJsonParse.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_json_parse,
      version: "0.1.0",
      elixir: "~> 1.12",
      compilers: Mix.compilers() ++ [:domo_compiler],
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:domo, path: ".."},
      {:jason, "~> 1.2"},
      {:exjsonpath, "~> 0.1"}
    ]
  end
end
