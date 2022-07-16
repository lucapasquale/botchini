defmodule Plug.Parsers.XML do
  @behaviour Plug.Parsers
  import Plug.Conn

  def init(opts) do
    opts
  end

  def parse(conn, _, "atom+xml", _headers, opts) do
    conn
    |> read_body(opts)
    |> decode()
  end

  def parse(conn, _type, _subtype, _headers, _opts) do
    {:next, conn}
  end

  defp decode({:ok, body, conn}) do
    {:ok, XmlToMap.naive_map(body), conn}
  rescue
    e -> raise Plug.Parsers.ParseError, exception: e
  end
end
