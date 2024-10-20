defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "8.12.2",
      elixir: "~> 1.17.0",
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
      extra_applications: [:logger, :runtime_tools, :elixir_xml_to_map]
    ]
  end

  defp deps do
    [
      # Discord
      {:nostrum, github: "BrandtHill/nostrum", runtime: Mix.env() != :test},
      # Phoenix
      {:phoenix, "~> 1.7.12"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.20.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      {:elixir_xml_to_map, "~> 3.1.0"},
      # Ecto
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.11.1"},
      {:postgrex, "~> 0.17.5"},
      # HTTP Client
      {:req, "~> 0.4.0"},
      {:exconstructor, "~> 1.2.13"},
      # Others
      {:quantum, "~> 3.0"},
      {:sentry, "~> 10.2.0"},
      {:hackney, "~> 1.8"},
      # Development and testing
      {:credo, "~> 1.7.7", only: [:dev, :test], runtime: false},
      {:patch, "~> 0.12.0", only: [:test]},
      {:faker, "~> 0.16", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind botchini", "esbuild botchini"],
      "assets.deploy": [
        "tailwind botchini --minify",
        "esbuild botchini --minify",
        "phx.digest"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
