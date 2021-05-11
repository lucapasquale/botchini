defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "3.1.0",
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Botchini.Application, []}
    ]
  end

  defp deps do
    [
      # Discord
      {:nostrum, "~> 0.4", runtime: Mix.env() != :test},
      # Ecto
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      # HTTP Client
      {:tesla, "~> 1.4.0"},
      {:hackney, "~> 1.17.0"},
      {:jason, ">= 1.0.0"},
      {:exconstructor, "~> 1.1.0"},
      # HTTP Server
      {:plug_cowboy, "~> 2.0"},
      # Logging
      {:ink, "~> 1.0"},
      # Development and testing
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:mock, "~> 0.3.0", only: :test},
      {:faker, "~> 0.16", only: :test}
    ]
  end

  defp aliases do
    [test: ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "test"]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
