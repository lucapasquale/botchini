defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "4.0.3",
      elixir: "~> 1.12",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: extra_applications(Mix.env()),
      mod: {Botchini.Application, []}
    ]
  end

  defp extra_applications(:dev), do: extra_applications(:all) ++ [:remix]
  defp extra_applications(_all), do: [:logger]

  defp deps do
    [
      # Discord
      {:nostrum, github: "Kraigie/nostrum", runtime: Mix.env() != :test},
      {:gun, "== 2.0.0-rc.2", override: true},
      # Ecto
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      # HTTP Client
      {:tesla, "~> 1.4.0"},
      {:hackney, "~> 1.17.0"},
      {:jason, ">= 1.0.0"},
      {:exconstructor, "~> 1.1.0"},
      # HTTP Server
      {:cowlib, ">= 2.11.0", override: true},
      {:plug_cowboy, "~> 2.0"},
      # Logging
      {:ink, "~> 1.0"},
      # Development and testing
      {:remix, "~> 0.0.1", only: :dev},
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
