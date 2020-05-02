defmodule Domo.MixProject do
  use Mix.Project

  def project do
    [
      app: :domo,
      version: "1.0.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:typed_struct, "~> 0.1.4"}
    ]
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README"],
      maintainers: ["Ivan Rublev"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/IvanRublev/domo"}
    ]
  end
end
