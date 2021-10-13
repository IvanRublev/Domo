defmodule Domo.MixProject do
  use Mix.Project

  @version "1.3.4"
  @repo_url "https://github.com/IvanRublev/Domo"

  def project do
    [
      app: :domo,
      version: @version,
      elixir: ">= 1.11.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: compilers(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      mix_project_stub: mix_project_stub(Mix.env()),

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
        "A library to ensure the consistency of structs modeling a business domain via their `t()` types and associated precondition functions."
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:benchmark), do: ["lib", "benchmark"]
  defp elixirc_paths(_), do: ["lib"]

  defp compilers(:benchmark), do: Mix.compilers() ++ [:domo_compiler]
  defp compilers(_), do: Mix.compilers()

  defp deps do
    [
      # Development and test dependencies
      {:ex_check, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:excoveralls, "~> 0.13.4", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},
      {:placebo, "~> 1.2", only: :test},
      {:ecto, ">= 0.0.0", optional: true},
      {:decimal, ">= 0.0.0", optional: true},

      # Documentation dependencies
      {:ex_doc, ">= 0.0.0", only: :docs, runtime: false},

      # Benchmark dependencies
      {:benchee, "~> 1.0", only: :benchmark, runtime: false},
      {:stream_data, "~> 0.5.0", only: :benchmark, runtime: false},
      {:profiler, "~> 0.1.0", only: :benchmark, runtime: false}
    ]
  end

  defp aliases do
    [
      benchmark: "run -e 'Benchmark.run()'",
      profile: "run -e 'Benchmark.Profile.run()'"
    ]
  end

  defp mix_project_stub(:test), do: MixProjectStubCorrect
  defp mix_project_stub(_), do: nil

  defp cli_env do
    [
      # Run mix test.watch in `:test` env.
      "test.watch": :test,

      # Always run Coveralls Mix tasks in `:test` env.
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.html": :test,

      # Use a custom env for docs.
      docs: :docs,

      # Use a custom env for benchmark and profile.
      benchmark: :benchmark,
      profile: :benchmark
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
