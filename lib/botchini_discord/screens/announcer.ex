defmodule BotchiniDiscord.Screens.Announcer do
  @moduledoc """
  Tells guilds about their screen shares on Discord. Guilds with a streams channel
  get a single message there listing everyone sharing, edited as screen shares
  go live and end. Other guilds get a message with the watch link in the channel
  a screen share was started from once it goes live, deleted when it ends
  """

  use GenServer

  require Logger

  alias Nostrum.Api.Message
  alias Nostrum.Error.ApiError

  alias Botchini.Screens
  alias Botchini.Screens.Room
  alias Botchini.Screens.Schema.StreamChannel
  alias BotchiniDiscord.Helpers
  alias BotchiniDiscord.Screens.ChannelName
  alias BotchiniDiscord.Screens.Responses.Components

  # Watch all links expire after a day, so the streams channels' messages get
  # fresh ones well before that, even when nobody shares for a while
  @refresh_links_ms :timer.hours(12)
  # Keeps the message under Discord's 2000 characters
  @max_listed_rooms 15
  # Discord allows renaming a channel twice every 10 minutes
  @renames_per_window 2
  @rename_window_ms :timer.minutes(10)

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Makes the channel the guild's streams channel, moving its message there
  """
  @spec set_channel(String.t(), String.t()) :: :ok | {:error, String.t()}
  def set_channel(guild_id, channel_id),
    do: GenServer.call(__MODULE__, {:set_channel, guild_id, channel_id})

  @impl true
  def init(nil) do
    # Stopping before Nostrum on shutdown lets terminate/2 still update the messages
    Process.flag(:trap_exit, true)
    Screens.subscribe()

    # messages: room id => {channel_id, message_id, title}, for guilds without a streams channel
    # guilds: guild id => guild(), for the others
    {:ok, %{messages: %{}, guilds: %{}}, {:continue, :load_channels}}
  end

  @impl true
  def handle_continue(:load_channels, state) do
    Process.send_after(self(), :refresh_links, @refresh_links_ms)

    guilds =
      Map.new(Screens.list_stream_channels(), fn %StreamChannel{discord_guild_id: guild_id} =
                                                   channel ->
        rooms = live_rooms(guild_id)
        Enum.each(rooms, fn {room_id, _room} -> Screens.subscribe(room_id) end)
        {_result, guild} = channel |> new_guild(rooms) |> update_status()

        {guild_id, sync_name(guild)}
      end)

    {:noreply, %{state | guilds: guilds}}
  end

  @impl true
  def handle_call({:set_channel, guild_id, channel_id}, _from, state) do
    previous = state.guilds[guild_id]
    rooms = if previous, do: previous.rooms, else: live_rooms(guild_id)

    with {:ok, message} <- post(channel_id, status_message(guild_id, rooms)),
         {:ok, channel} <- Screens.put_stream_channel(guild_id, channel_id, to_string(message.id)) do
      if previous, do: leave_channel(previous, channel_id)

      state = if previous, do: state, else: move_rooms(state, rooms)
      {:reply, :ok, put_in(state.guilds[guild_id], channel |> new_guild(rooms) |> sync_name())}
    else
      {:error, %Ecto.Changeset{}} -> {:reply, {:error, "couldn't save the channel"}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:screen_room, :live, %Room{} = room}, state) do
    if Map.has_key?(state.guilds, room.guild_id) do
      Screens.subscribe(room.id)
      {result, state} = update_rooms(state, room.guild_id, &Map.put(&1, room.id, room))
      if result == :error, do: announcement_failed(room)

      {:noreply, state}
    else
      case post(room.channel_id, live_message(room)) do
        {:ok, message} ->
          Screens.subscribe(room.id)

          {:noreply,
           put_in(state.messages[room.id], {message.channel_id, message.id, room.title})}

        {:error, _reason} ->
          announcement_failed(room)
          {:noreply, state}
      end
    end
  end

  def handle_info({:screen_room, :updated, %Room{} = room}, state) do
    listed = get_in(state.guilds, [room.guild_id, :rooms, room.id])
    message = state.messages[room.id]

    cond do
      listed && listed.title != room.title ->
        {_result, state} = update_rooms(state, room.guild_id, &Map.put(&1, room.id, room))
        {:noreply, state}

      message && elem(message, 2) != room.title ->
        {channel_id, message_id, _title} = message
        edit({channel_id, message_id}, live_message(room))
        {:noreply, put_in(state.messages[room.id], {channel_id, message_id, room.title})}

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:screen_room, :ended, %Room{} = room}, state) do
    Screens.unsubscribe(room.id)
    {message, messages} = Map.pop(state.messages, room.id)
    if message, do: delete(message)
    state = %{state | messages: messages}

    if get_in(state.guilds, [room.guild_id, :rooms, room.id]) do
      {_result, state} = update_rooms(state, room.guild_id, &Map.delete(&1, room.id))
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(:refresh_links, state) do
    Process.send_after(self(), :refresh_links, @refresh_links_ms)

    guilds =
      Map.new(state.guilds, fn {guild_id, guild} ->
        {_result, guild} = update_status(guild)
        {guild_id, guild}
      end)

    {:noreply, %{state | guilds: guilds}}
  end

  def handle_info({:sync_name, guild_id}, state) do
    case state.guilds[guild_id] do
      nil -> {:noreply, state}
      guild -> {:noreply, put_in(state.guilds[guild_id], sync_name(%{guild | rename_timer: nil}))}
    end
  end

  # A rename task finished, or crashed
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish_rename(state, ref, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state),
    do: {:noreply, finish_rename(state, ref, :error)}

  def handle_info(_message, state), do: {:noreply, state}

  # Rooms only live in memory, so a restart ends every screen share
  @impl true
  def terminate(_reason, state) do
    Enum.each(state.messages, fn {_room_id, message} -> delete(message) end)

    Enum.each(state.guilds, fn {_guild_id, guild} ->
      update_status(%{guild | rooms: %{}})
      if guild.named_live? != false and rename_allowed?(guild), do: rename(guild.channel, false)
    end)
  end

  @typep guild :: %{
           channel: StreamChannel.t(),
           rooms: %{String.t() => Room.t()},
           # Whether the channel's name is marked as live, nil until it's checked
           named_live?: boolean() | nil,
           # The rename task running, and whether it marks the name as live
           renaming: {reference(), boolean()} | nil,
           # When the channel was renamed, in monotonic milliseconds
           renames: [integer()],
           rename_timer: reference() | nil
         }

  @spec new_guild(StreamChannel.t(), map()) :: guild()
  defp new_guild(channel, rooms) do
    %{
      channel: channel,
      rooms: rooms,
      named_live?: nil,
      renaming: nil,
      renames: [],
      rename_timer: nil
    }
  end

  # The broadcaster still has the watch link from the /stream start reply
  defp announcement_failed(room), do: Screens.broadcast_announcement_failed(room)

  defp live_rooms(guild_id) do
    guild_id
    |> Screens.list_rooms()
    |> Enum.filter(& &1.live?)
    |> Map.new(&{&1.id, &1})
  end

  # Rooms announced where they were started from get listed in the streams channel instead
  defp move_rooms(state, rooms) do
    Enum.reduce(rooms, state, fn {room_id, _room}, state ->
      case Map.pop(state.messages, room_id) do
        {nil, _messages} ->
          Screens.subscribe(room_id)
          state

        {message, messages} ->
          delete(message)
          %{state | messages: messages}
      end
    end)
  end

  defp update_rooms(state, guild_id, fun) do
    guild = Map.update!(state.guilds[guild_id], :rooms, fun)
    {result, guild} = update_status(guild)

    {result, put_in(state.guilds[guild_id], sync_name(guild))}
  end

  # Renames run in tasks, as Nostrum holds requests over Discord's rate limit until
  # they're allowed, and one at a time per channel, so they finish in order
  defp sync_name(%{renaming: {_ref, _live?}} = guild), do: guild

  defp sync_name(guild) do
    live? = guild.rooms != %{}
    guild = %{guild | renames: recent_renames(guild)}

    cond do
      guild.named_live? == live? ->
        guild

      not rename_allowed?(guild) ->
        schedule_sync_name(guild)

      true ->
        task = Task.async(fn -> ChannelName.rename(guild.channel.discord_channel_id, live?) end)
        %{guild | renaming: {task.ref, live?}}
    end
  end

  defp recent_renames(guild) do
    since = System.monotonic_time(:millisecond) - @rename_window_ms
    Enum.filter(guild.renames, &(&1 > since))
  end

  defp rename_allowed?(guild), do: length(recent_renames(guild)) < @renames_per_window

  # Tries again once the oldest rename leaves the window, and only renames if it's still needed then
  defp schedule_sync_name(%{rename_timer: nil} = guild) do
    wait = Enum.min(guild.renames) + @rename_window_ms - System.monotonic_time(:millisecond)
    timer = Process.send_after(self(), {:sync_name, guild.channel.discord_guild_id}, wait)

    %{guild | rename_timer: timer}
  end

  defp schedule_sync_name(guild), do: guild

  defp finish_rename(state, ref, result) do
    case Enum.find(state.guilds, fn {_guild_id, guild} -> match?({^ref, _}, guild.renaming) end) do
      nil ->
        state

      {guild_id, %{renaming: {_ref, live?}} = guild} ->
        renames =
          if result == {:ok, true},
            do: [System.monotonic_time(:millisecond) | guild.renames],
            else: guild.renames

        # A failed rename isn't retried until the next change, so a missing permission doesn't loop
        guild = %{guild | renaming: nil, named_live?: live?, renames: renames}
        put_in(state.guilds[guild_id], sync_name(guild))
    end
  end

  defp rename(channel, live?), do: ChannelName.rename(channel.discord_channel_id, live?)

  # The old streams channel loses its message, and its live mark
  defp leave_channel(previous, channel_id) do
    delete_status(previous.channel)

    if previous.channel.discord_channel_id != channel_id and previous.named_live? != false,
      do: Task.start(fn -> rename(previous.channel, false) end)
  end

  # Edits the guild's message in its streams channel, or posts it again if it's gone
  defp update_status(%{channel: channel, rooms: rooms} = guild) do
    message = status_message(channel.discord_guild_id, rooms)

    result =
      case channel.discord_message_id &&
             edit({channel.discord_channel_id, channel.discord_message_id}, message) do
        {:ok, _message} -> {:ok, channel}
        # Someone deleted it
        {:error, %ApiError{response: %{code: 10_008}}} -> repost_status(channel, message)
        nil -> repost_status(channel, message)
        {:error, _error} -> :error
      end

    case result do
      {:ok, channel} -> {:ok, %{guild | channel: channel}}
      _error -> {:error, guild}
    end
  end

  defp repost_status(channel, message) do
    with {:ok, posted} <- post(channel.discord_channel_id, message) do
      Screens.put_stream_channel(
        channel.discord_guild_id,
        channel.discord_channel_id,
        to_string(posted.id)
      )
    end
  end

  defp delete_status(%StreamChannel{discord_message_id: nil}), do: :ok

  defp delete_status(%StreamChannel{} = channel),
    do: delete({channel.discord_channel_id, channel.discord_message_id, nil})

  defp status_message(guild_id, rooms) do
    %{
      content: status_content(rooms |> Map.values() |> Enum.sort_by(& &1.started_at, DateTime)),
      components: [Components.watch_all_screens(guild_id)],
      allowed_mentions: :none
    }
  end

  defp status_content([]) do
    """
    ### Screen shares
    Nobody is sharing their screen right now.

    -# Run `/stream start` to share your screen, or `/stream obs` to stream from OBS
    """
  end

  defp status_content(rooms) do
    {listed, hidden} = Enum.split(rooms, @max_listed_rooms)

    lines =
      Enum.map(listed, fn room ->
        "🔴 **#{Helpers.escape_markdown(room.title)}** by <@#{room.owner_id}>"
      end)

    lines = if hidden == [], do: lines, else: lines ++ ["…and #{length(hidden)} more"]

    """
    ### Screen shares
    #{Enum.join(lines, "\n")}

    -# Run `/stream start` to share your screen, or `/stream obs` to stream from OBS
    """
  end

  defp live_message(room) do
    %{
      content:
        "🔴 <@#{room.owner_id}> is sharing their screen: **#{Helpers.escape_markdown(room.title)}**",
      components: [Components.watch_all_screens(room.guild_id)],
      allowed_mentions: :none
    }
  end

  # The requests never raise out of here, as a crash would lose every message being tracked

  defp post(channel_id, message) do
    case Message.create(to_id(channel_id), message) do
      {:ok, posted} ->
        {:ok, posted}

      {:error, error} ->
        Logger.error("Failed to post screen share message: #{describe_error(error)}",
          channel_id: channel_id,
          error: inspect(error)
        )

        {:error, describe_error(error)}
    end
  rescue
    error ->
      Logger.error("Failed to post screen share message: " <> Exception.message(error))
      {:error, "request failed"}
  end

  defp delete({channel_id, message_id, _title}) do
    case Message.delete(to_id(channel_id), to_id(message_id)) do
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
    with {:error, error} = result <- Message.edit(to_id(channel_id), to_id(message_id), message) do
      Logger.warning("Failed to edit screen share message: #{describe_error(error)}",
        error: inspect(error)
      )

      result
    end
  rescue
    error ->
      Logger.warning("Failed to edit screen share message: " <> Exception.message(error))
      {:error, error}
  end

  # Ids are strings in the database, and integers in Nostrum's structs
  defp to_id(id) when is_integer(id), do: id
  defp to_id(id) when is_binary(id), do: String.to_integer(id)

  # Interactions reply without any channel permissions, so the bot can answer
  # /stream start in a channel it isn't allowed to post in
  defp describe_error(%ApiError{status_code: 403}),
    do: "missing the View Channel or Send Messages permission in the channel"

  defp describe_error(%ApiError{status_code: status}), do: "Discord answered #{status}"
  defp describe_error(_error), do: "request failed"
end
