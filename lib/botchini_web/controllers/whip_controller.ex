defmodule BotchiniWeb.WhipController do
  @moduledoc """
  WHIP endpoint, so members can share their screen from OBS with their stream key
  """

  use BotchiniWeb, :controller

  alias Botchini.Screens
  alias Botchini.Screens.Room

  @max_offer_bytes 64_000

  def create(conn, _params) do
    with {:ok, stream_key} <- authorize(conn),
         {:ok, offer, conn} <- read_offer(conn),
         {:ok, room} <- Screens.start_stream_key_room(stream_key),
         {:ok, answer, session_id} <- Room.publish_whip(room.id, offer) do
      conn
      |> put_resp_header("location", url(~p"/api/whip/#{room.id}/#{session_id}"))
      |> put_resp_content_type("application/sdp", nil)
      |> send_resp(201, answer)
    else
      {:error, :unauthorized} -> send_resp(conn, 401, "")
      {:error, :unsupported_media_type} -> send_resp(conn, 415, "")
      {:error, :too_large} -> send_resp(conn, 413, "")
      {:error, _reason} -> send_resp(conn, 400, "")
    end
  end

  def delete(conn, %{"room_id" => room_id, "session_id" => session_id}) do
    with {:ok, stream_key} <- authorize(conn),
         %Room{} = room <- Screens.get_room(room_id),
         true <- room.guild_id == stream_key.discord_guild_id,
         true <- room.owner_id == stream_key.discord_user_id,
         :ok <- Room.end_whip(room.id, session_id) do
      send_resp(conn, 200, "")
    else
      {:error, :unauthorized} -> send_resp(conn, 401, "")
      _not_found -> send_resp(conn, 404, "")
    end
  end

  def update(conn, _params), do: send_resp(conn, 405, "")

  defp authorize(conn) do
    with ["Bearer " <> key] <- get_req_header(conn, "authorization"),
         %{} = stream_key <- Screens.get_stream_key(String.trim(key)) do
      {:ok, stream_key}
    else
      _ -> {:error, :unauthorized}
    end
  end

  defp read_offer(conn) do
    with ["application/sdp" <> _] <- get_req_header(conn, "content-type"),
         {:ok, offer, conn} <- Plug.Conn.read_body(conn, length: @max_offer_bytes) do
      {:ok, offer, conn}
    else
      {:more, _partial, _conn} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
      _content_type -> {:error, :unsupported_media_type}
    end
  end
end
