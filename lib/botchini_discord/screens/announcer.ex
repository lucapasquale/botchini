defmodule BotchiniDiscord.Screens.Announcer do
  @moduledoc """
  Posts a message with the watch link in the channel a screen share was started
  from once the broadcaster goes live, and deletes it when the room closes
  """

  use GenServer

  require Logger

  alias Nostrum.Api.Message
  alias Nostrum.Error.ApiError

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias BotchiniDiscord.Helpers
  alias BotchiniDiscord.Screens.Responses.Components

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    # Stopping before Nostrum on shutdown lets terminate/2 still delete the messages
    Process.flag(:trap_exit, true)
    Screens.subscribe()

    # room id => {channel_id, message_id, title}
    {:ok, %{}}
  end

  @impl true
  def handle_info({:screen_room, :live, %Room{} = room}, messages) do
    case announce(room) do
      {:ok, message} ->
        Screens.subscribe(room.id)
        {:noreply, Map.put(messages, room.id, {message.channel_id, message.id, room.title})}

      # The broadcaster still has the watch link from the /screen start reply
      :error ->
        Screens.broadcast_announcement_failed(room)
        {:noreply, messages}
    end
  end

  def handle_info({:screen_room, :updated, %Room{} = room}, messages) do
    case Map.fetch(messages, room.id) do
      {:ok, {channel_id, message_id, title}} when title != room.title ->
        edit({channel_id, message_id}, live_message(room))
        {:noreply, Map.put(messages, room.id, {channel_id, message_id, room.title})}

      _ ->
        {:noreply, messages}
    end
  end

  def handle_info({:screen_room, :ended, %Room{} = room}, messages) do
    Screens.unsubscribe(room.id)
    {message, messages} = Map.pop(messages, room.id)
    if message, do: delete(message)

    {:noreply, messages}
  end

  def handle_info(_message, messages), do: {:noreply, messages}

  # Rooms only live in memory, so a restart ends every screen share
  @impl true
  def terminate(_reason, messages) do
    Enum.each(messages, fn {_room_id, message} -> delete(message) end)
  end

  defp live_message(room) do
    %{
      content:
        "🔴 <@#{room.owner_id}> is sharing their screen: **#{Helpers.escape_markdown(room.title)}**",
      components: [Components.watch_all_screens(room.guild_id)],
      allowed_mentions: :none
    }
  end

  defp announce(room) do
    case Message.create(String.to_integer(room.channel_id), live_message(room)) do
      {:ok, message} ->
        {:ok, message}

      {:error, error} ->
        Logger.error("Failed to announce screen share: #{describe_error(error)}",
          channel_id: room.channel_id,
          error: inspect(error)
        )

        :error
    end
  rescue
    # A crash would lose the messages of every other room being tracked
    error ->
      Logger.error("Failed to announce screen share: " <> Exception.message(error))
      :error
  end

  defp delete({channel_id, message_id, _title}) do
    case Message.delete(channel_id, message_id) do
      {:error, error} ->
        Logger.warning("Failed to delete screen share message: #{describe_error(error)}",
          error: inspect(error)
        )

      _ok ->
        :ok
    end
  rescue
    error -> Logger.warning("Failed to delete screen share message: " <> Exception.message(error))
  end

  defp edit({channel_id, message_id}, message) do
    case Message.edit(channel_id, message_id, message) do
      {:ok, _message} ->
        :ok

      {:error, error} ->
        Logger.warning("Failed to edit screen share message: #{describe_error(error)}",
          error: inspect(error)
        )
    end
  rescue
    error -> Logger.warning("Failed to edit screen share message: " <> Exception.message(error))
  end

  # Interactions reply without any channel permissions, so the bot can answer
  # /screen start in a channel it isn't allowed to post in
  defp describe_error(%ApiError{status_code: 403}),
    do: "missing the View Channel or Send Messages permission in the channel"

  defp describe_error(%ApiError{status_code: status}), do: "Discord answered #{status}"
  defp describe_error(_error), do: "request failed"
end
