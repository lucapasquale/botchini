defmodule Botchini.PromEx do
  @moduledoc """
  Prometheus metrics of the app, Phoenix, LiveView, the database and the BEAM,
  with their Grafana dashboards
  """

  use PromEx, otp_app: :botchini

  @impl true
  def plugins do
    [
      PromEx.Plugins.Application,
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix, router: BotchiniWeb.Router, endpoint: BotchiniWeb.Endpoint},
      {PromEx.Plugins.Ecto, repos: [Botchini.Repo]},
      PromEx.Plugins.PhoenixLiveView,
      Botchini.PromEx.BotchiniPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "phoenix_live_view.json"}
    ]
  end
end
