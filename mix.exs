defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "8.7.0",
      elixir: "~> 1.15",
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
      # Phoenix
      {:phoenix, "~> 1.6.16"},
      {:phoenix_html, "~> 3.3.1"},
      {:phoenix_live_dashboard, "~> 0.6"},
      {:phoenix_live_reload, "~> 1.4.1", only: :dev},
      {:phoenix_live_view, "~> 0.17.14"},
      {:floki, ">= 0.34.2", only: :test},
      {:esbuild, "~> 0.7", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.22.1"},
      {:jason, "~> 1.4.0"},
      {:plug_cowboy, "~> 2.6.1"},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:petal_components, "~> 0.17"},
      {:elixir_xml_to_map, "~> 2.0"},
      # Ecto
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.9.2"},
      {:postgrex, ">= 0.16.5"},
      # HTTP Client
      {:tesla, "~> 1.6.0"},
      {:gun, "~> 2.0", override: true},
      {:hackney, "~> 1.17.0"},
      {:exconstructor, "~> 1.1.0"},
      # Helpers
      {:ink, "~> 1.0"},
      {:quantum, "~> 3.0"},
      # Development and testing
      {:exsync, "~> 0.2", only: :dev},
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false},
      {:patch, "~> 0.12.0", only: [:test]},
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
