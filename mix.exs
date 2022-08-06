defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "6.6.3",
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
      extra_applications: [:logger, :elixir_xml_to_map],
      mod: {Botchini.Application, []}
    ]
  end

  defp deps do
    [
      # Discord
      {:nostrum, "~> 0.6", runtime: Mix.env() != :test},
      {:cowlib, "~> 2.11", hex: :remedy_cowlib, override: true},
      # Phoenix
      {:phoenix, "~> 1.6.10"},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.17.5"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.6"},
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.5"},
      {:tailwind, "~> 0.1", runtime: Mix.env() == :dev},
      {:elixir_xml_to_map, "~> 2.0"},
      # Ecto
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.6"},
      {:postgrex, ">= 0.0.0"},
      # HTTP Client
      {:tesla, "~> 1.4.0"},
      {:hackney, "~> 1.17.0"},
      {:exconstructor, "~> 1.1.0"},
      # Helpers
      {:ink, "~> 1.0"},
      {:quantum, "~> 3.0"},
      # Development and testing
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
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
