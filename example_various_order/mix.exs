defmodule ExampleVariousOrder.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_various_order,
      version: "0.1.0",
      elixir: "~> 1.10",
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
      {:norm, "~> 0.12.0"}
    ]
  end
end
