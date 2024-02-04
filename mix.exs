defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "8.9.1",
      elixir: "~> 1.16.1",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      mod: {Botchini.Application, []},
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:dev), do: extra_applications(:all) ++ [:exsync]
  defp extra_applications(_all), do: [:logger, :elixir_xml_to_map]

  defp deps do
    [
      # Discord
      {:nostrum, git: "https://github.com/Kraigie/nostrum.git", runtime: Mix.env() != :test},
      {:cowlib, "~> 2.11", hex: :remedy_cowlib, override: true},
      # Ecto
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.11.1"},
      {:postgrex, ">= 0.17.4"},
      # HTTP Client
      {:tesla, "~> 1.8.0"},
      {:gun, "~> 2.0", override: true},
      {:hackney, "~> 1.20.1"},
      {:exconstructor, "~> 1.2.10"},
      # Helpers
      {:ink, "~> 1.0"},
      {:quantum, "~> 3.0"},
      # Development and testing
      {:exsync, "~> 0.2", only: :dev},
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false},
      {:patch, "~> 0.13.0", only: [:test]},
      {:faker, "~> 0.16", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
