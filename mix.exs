defmodule Domo.MixProject do
  use Mix.Project

  @version "1.0.0"
  @repo_url "https://github.com/IvanRublev/Domo"

  def project do
    [
      app: :domo,
      version: @version,
      elixir: ">= 1.10.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Tools
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: cli_env(),

      # Docs
      name: "Domo",
      docs: [
        main: "Domo",
        source_url: @repo_url,
        source_ref: "v#{@version}"
      ],

      # Package
      package: package(),
      description:
        "A library to model a business domain with type-safe structs " <>
          "and composable tagged tuples."
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Development and test dependencies
      {:ex_check, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:credo, "~> 1.4", only: :dev, runtime: false},
      {:excoveralls, "~> 0.13.0", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},

      # Project dependencies
      {:typed_struct, ">= 0.0.0"},

      # Documentation dependencies
      {:ex_doc, "~> 0.19", only: :docs, runtime: false}
    ]
  end

  defp cli_env do
    [
      # Run mix test.watch in `:test` env.
      "test.watch": :test,

      # Always run Coveralls Mix tasks in `:test` env.
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.html": :test,

      # Use a custom env for docs.
      docs: :docs
    ]
  end

  defp package do
    [
      files: [".formatter.exs", "lib", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url}
    ]
  end
end
