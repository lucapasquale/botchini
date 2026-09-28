defmodule BotchiniDiscord.Screens.Announcer do
  @moduledoc """
  Posts a message with the watch link in the channel a screen share was started
  from once the broadcaster goes live, and marks it as ended when the room closes
  """

  use GenServer

  require Logger

  alias Nostrum.Api.Message

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniDiscord.Screens.Responses.Components

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    # Stopping before Nostrum on shutdown lets terminate/2 still mark the messages as ended
    Process.flag(:trap_exit, true)
    Screens.subscribe()

    # room id => {channel_id, message_id}
    {:ok, %{}}
  end

  @impl true
  def handle_info({:screen_room, :live, %Room{} = room}, messages) do
    case Message.create(String.to_integer(room.channel_id), live_message(room)) do
      {:ok, message} ->
        {:noreply, Map.put(messages, room.id, {message.channel_id, message.id})}

      {:error, error} ->
        Logger.error("Failed to announce screen share", error: inspect(error))
        {:noreply, messages}
    end
  end

  def handle_info({:screen_room, :ended, %Room{} = room}, messages) do
    {message, messages} = Map.pop(messages, room.id)
    if message, do: mark_ended(message, room)

    {:noreply, messages}
  end

  def handle_info(_message, messages), do: {:noreply, messages}

  # Rooms only live in memory, so a restart ends every screen share
  @impl true
  def terminate(_reason, messages) do
    Enum.each(messages, fn {_room_id, message} -> mark_ended(message, nil) end)
  end

  defp live_message(room) do
    %{
      content: "🔴 <@#{room.owner_id}> is sharing their screen: **#{room.title}**",
      components: [Components.watch_screen(room)],
      allowed_mentions: %{parse: []}
    }
  end

  defp mark_ended({channel_id, message_id}, room) do
    content =
      case room do
        %Room{} -> "⚫ <@#{room.owner_id}> stopped sharing their screen: **#{room.title}**"
        nil -> "⚫ This screen share ended"
      end

    case Message.edit(channel_id, message_id, %{
           content: content,
           components: [],
           allowed_mentions: %{parse: []}
         }) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.warning("Failed to end screen share message", error: inspect(error))
    end
  end
end
