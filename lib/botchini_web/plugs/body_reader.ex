defmodule BotchiniWeb.CacheBodyReader do
  @moduledoc """
  Plug for saving raw body on the connection
  """

  @spec read_body(Plug.Conn.t(), keyword()) :: {:ok, binary, Plug.Conn.t()}
  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
    {:ok, body, conn}
  end
end
