defmodule BotchiniWeb.MetricsPlug do
  @moduledoc """
  Serves the PromEx metrics on their own port, so they aren't exposed on the public site
  """

  use Plug.Builder

  plug PromEx.Plug, prom_ex_module: Botchini.PromEx, path: "/metrics"
  plug :not_found

  defp not_found(conn, _opts), do: send_resp(conn, 404, "Not found")
end
