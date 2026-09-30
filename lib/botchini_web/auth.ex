defmodule BotchiniWeb.Auth do
  @moduledoc """
  Keeps the screen sharing pages for logged in users. The Discord login puts the
  user's id and name in the session, which LiveViews read as `current_user`
  """

  use BotchiniWeb, :verified_routes

  import Phoenix.Controller, only: [redirect: 2]
  import Plug.Conn, except: [assign: 3]

  @doc """
  Sends visitors who aren't logged in to the login page, which sends them back after
  """
  @spec require_user(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def require_user(conn, _opts) do
    if get_session(conn, "discord_user_id") do
      conn
    else
      conn
      |> redirect(to: ~p"/auth/login?#{[return_to: conn.request_path]}")
      |> halt()
    end
  end

  @spec log_in(Plug.Conn.t(), Botchini.Discord.OAuth.user()) :: Plug.Conn.t()
  def log_in(conn, user) do
    conn
    |> configure_session(renew: true)
    |> put_session("discord_user_id", user.id)
    |> put_session("discord_user_name", user.name)
  end

  @doc """
  Whether the logged in user belongs to the guild whose screens they're opening
  """
  @spec member_status(Phoenix.LiveView.Socket.t(), String.t()) :: :member | :not_member | :error
  def member_status(socket, guild_id),
    do: Botchini.Discord.check_member(guild_id, socket.assigns.current_user.id)

  # The LiveView mounts again over the websocket, where the plug doesn't run
  @spec on_mount(:require_user, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont | :halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:require_user, _params, session, socket) do
    case session do
      %{"discord_user_id" => id, "discord_user_name" => name} ->
        {:cont, Phoenix.Component.assign(socket, :current_user, %{id: id, name: name})}

      _logged_out ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/auth/login")}
    end
  end
end
