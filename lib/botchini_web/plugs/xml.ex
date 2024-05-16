defmodule BotchiniWeb.Plugs.XML do
  @moduledoc """
  Plug for decoding XML requests
  """

  @behaviour Plug.Parsers
  import Plug.Conn

  def init(opts) do
    opts
  end

  def parse(conn, _, "atom+xml", _headers, opts) do
    {:ok, body, conn} = read_body(conn, opts)
    conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])

    decode({:ok, body, conn})
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:ok, body, conn}) do
    {:ok, XmlToMap.naive_map(body), conn}
  end
end
