defmodule ExampleTypedIntegrations.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_typed_integrations,
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
      {:domo, path: ".."},
      {:typed_struct, ">= 0.0.0"},
      {:typed_ecto_schema, ">= 0.0.0"}
    ]
  end
end
