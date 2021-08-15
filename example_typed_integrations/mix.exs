defmodule ExampleTypedIntegrations.MixProject do
  use Mix.Project

  def project do
    [
      app: :example_typed_integrations,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:domo_compiler],
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
      {:typed_struct, "~> 0.2.1"},
      {:typed_ecto_schema, "~> 0.3.0"}
    ]
  end
end
