defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "8.15.0",
      elixir: "~> 1.20",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      listeners: [Phoenix.CodeReloader]
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
      {:nostrum, github: "Kraigie/nostrum"},
      # Phoenix
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.3"},
      {:phoenix_live_reload, "~> 1.6", only: :dev},
      {:phoenix_live_view, "~> 1.1"},
      {:floki, ">= 0.37.1", only: :test},
      {:phoenix_live_dashboard, "~> 0.9"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.23"},
      {:finch, "~> 0.21"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.3"},
      {:bandit, "~> 1.10"},
      {:elixir_xml_to_map, "~> 3.1.0"},
      # Ecto
      {:phoenix_ecto, "~> 4.4"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      # HTTP Client
      {:req, "~> 0.5"},
      # Observability - OpenTelemetry (traces)
      {:opentelemetry, "~> 1.5"},
      {:opentelemetry_api, "~> 1.4"},
      {:opentelemetry_exporter, "~> 1.8"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      # Observability - Prometheus metrics
      {:prom_ex, "~> 1.9"},
      # Observability - Structured JSON logging
      {:logger_json, "~> 7.0"},
      # Others
      {:quantum, "~> 3.0"},
      # Development and testing
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:patch, "~> 0.16.0", only: [:test]},
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
