defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:nostrum, "~> 0.4"},
      # Ecto
      {:ecto_sql, "~> 3.2"},
      {:postgrex, "~> 0.15"},
      # HTTP Client
      {:tesla, "~> 1.4.0"},
      {:hackney, "~> 1.17.0"},
      {:jason, ">= 1.0.0"},
      # HTTP Server
      {:plug_cowboy, "~> 2.0"}
    ]
  end
end
