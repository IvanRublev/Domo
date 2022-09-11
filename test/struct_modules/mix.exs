defmodule TestStructModules.MixProject do
  use Mix.Project

  def project do
    [
      app: :test_struct_modules,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      compilers: [:domo_compiler] ++ Mix.compilers(),
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
      {:domo, path: "../.."},
      {:ecto, ">= 0.0.0", optional: true}
    ]
  end
end
