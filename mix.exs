defmodule Botchini.MixProject do
  use Mix.Project

  def project do
    [
      app: :botchini,
      version: "8.9.1",
      elixir: "~> 1.16.1",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Botchini.Application, []},
      extra_applications: extra_applications(Mix.env())
    ]
  end

  defp extra_applications(:dev), do: extra_applications(:all) ++ [:exsync]
  defp extra_applications(_all), do: [:logger, :runtime_tools]

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Discord
      {:nostrum, git: "https://github.com/Kraigie/nostrum.git", runtime: Mix.env() != :test},
      {:cowlib, "~> 2.11", hex: :remedy_cowlib, override: true},
      # Phoenix
      {:phoenix, "~> 1.7.11"},
      {:phoenix_ecto, "~> 4.4"},
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
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.2"},
      # Ecto
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
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.drop --quiet", "ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind botchini", "esbuild botchini"],
      "assets.deploy": [
        "tailwind botchini --minify",
        "esbuild botchini --minify",
        "phx.digest"
      ]
    ]
  end
end
