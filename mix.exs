defmodule Domo.MixProject do
  use Mix.Project

  @version "1.5.17"
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

      # Tools
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: cli_env(),

      # Docs
      name: "Domo",
      docs: [
        extras: [
          "LICENSE.md": [title: "License"],
          "README.md": [title: "Readme"]
        ],
        main: "readme",
        source_url: @repo_url,
        source_ref: "v#{@version}",
        formatters: ["html"]
      ],

      # Package
      package: package(),
      description: "A library to validate values of nested structs with their type spec `t()` and associated precondition functions."
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support", out_of_project_tmp_path()]
  defp elixirc_paths(_), do: ["lib", "lib_std"]

  def out_of_project_tmp_path do
    Path.expand("../Domo_tmp", __DIR__)
  end

  def out_of_project_tmp_path(path) do
    Path.join([out_of_project_tmp_path(), path])
  end

  defp compilers(_), do: Mix.compilers()

  defp deps do
    [
      # Development and test dependencies
      {:ex_check, if(ex_before_12?(), do: "0.15.0", else: ">= 0.0.0"), only: :dev, runtime: false},
      {:credo, if(ex_before_12?(), do: "1.6.0", else: "~> 1.6"), only: :dev, runtime: false},
      {:excoveralls, "~> 0.13.4", only: :test, runtime: false},
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},
      {:placebo, "~> 1.2", only: :test},
      {:ecto, ">= 0.0.0", optional: true},
      {:decimal, ">= 0.0.0", optional: true},
      {:nimble_parsec, if(ex_before_12?(), do: "1.1.0", else: "~> 1.1")},
      # Documentation dependencies
      {:ex_doc, if(ex_before_12?(), do: "0.26.0", else: "~> 0.26.0"), only: :docs, runtime: false}
    ]
  end

  defp ex_before_12? do
    [1, minor, _] = ex_version()
    minor < 12
  end

  defp ex_version do
    :elixir
    |> Application.spec(:vsn)
    |> to_string()
    |> String.replace(~r/-.*$/, "")
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  end

  defp aliases do
    [
      benchmark: "cmd --cd ./benchmark_ecto_domo mix do deps.unlock --all + deps.get + benchmark",
      clean: ["clean", "cmd --cd ./benchmark_ecto_domo mix clean --deps", &clean_test_structs/1, &clean_out_of_project_tmp_path/1],
      test: [&clean_out_of_project_tmp_path/1, "test"]
    ]
  end

  defp clean_test_structs(_) do
    path = Application.fetch_env!(:domo, :test_structs_path)
    Mix.shell().cmd("mix clean --deps", cd: path, env: [{"MIX_ENV", "test"}])
  end

  defp clean_out_of_project_tmp_path(_) do
    File.rm_rf(out_of_project_tmp_path())
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
      files: [".formatter.exs", "lib", "mix.exs", "README.md", "LICENSE.md"],
      licenses: ["MIT"],
      links: %{"GitHub" => @repo_url}
    ]
  end
end
