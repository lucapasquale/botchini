defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "2.1.2",
      elixir: "~> 1.11",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
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
      {:ecto_sql, "~> 3.5.4"},
      {:postgrex, "~> 0.15"},
      # HTTP Client
      {:tesla, "~> 1.4.0"},
      {:hackney, "~> 1.17.0"},
      {:jason, ">= 1.0.0"},
      # HTTP Server
      {:plug_cowboy, "~> 2.0"},
      # Development and testing
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [test: ["ecto.create --quiet", "ecto.migrate", "test"]]
  end
end
