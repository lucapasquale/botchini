defmodule Botchini.Screens do
  @moduledoc """
  Screen sharing rooms, where a member broadcasts their screen from the browser
  to the other members watching it. Rooms only live in memory, and each one gets
  unguessable ids that stop working once it ends
  """

  alias Botchini.Repo
  alias Botchini.Screens.{Presence, Room, RoomSupervisor}
  alias Botchini.Screens.Schema.{ScreenSettings, StreamChannel, StreamKey}

  @topic "screens"

  @defaults [
    ice_servers: [],
    ice_port_range: nil,
    announced_ip: nil,
    max_viewers: 20,
    # How long the broadcaster has to go live after the room is made
    start_timeout_ms: :timer.minutes(10),
    # How long the room waits for an OBS broadcaster to come back after disconnecting
    reconnect_timeout_ms: :timer.minutes(2),
    # Browser broadcasters come back on their own within seconds after a network
    # blip, and can't resume after closing or reloading the tab, which needs a
    # click to share again. So a closed tab ends the stream soon
    tab_reconnect_timeout_ms: :timer.seconds(15),
    max_duration_ms: :timer.hours(12),
    # How long a member has to come back before leaving is shown in the activity
    activity_leave_grace_ms: :timer.seconds(5)
  ]

  @spec config() :: Keyword.t()
  def config do
    Keyword.merge(@defaults, Application.get_env(:botchini, __MODULE__, []))
  end

  @type start_attrs :: %{
          title: String.t(),
          guild_id: String.t(),
          channel_id: String.t() | nil,
          owner_id: String.t(),
          owner_name: String.t()
        }

  @doc """
  Starts a room for the owner. An owner has at most one room per guild,
  so their existing one is returned if it's still running
  """
  @spec start_room(start_attrs()) :: {:ok, Room.t()} | {:error, term()}
  def start_room(attrs) do
    case find_owner_room(attrs.guild_id, attrs.owner_id) do
      %Room{} = room ->
        {:ok, room}

      nil ->
        room =
          struct!(Room, Map.put(attrs, :id, random_id()))

        with {:ok, _pid} <- DynamicSupervisor.start_child(RoomSupervisor, {Room, room}),
             do: Room.info(room.id)
    end
  end

  @spec get_room(String.t()) :: Room.t() | nil
  def get_room(room_id) when is_binary(room_id) do
    case Room.info(room_id) do
      {:ok, room} -> room
      {:error, :not_found} -> nil
    end
  end

  @spec list_rooms(String.t()) :: [Room.t()]
  def list_rooms(guild_id) do
    Registry.select(Botchini.Screens.Registry, [
      {{:"$1", :_, {guild_id, :_}}, [], [:"$1"]}
    ])
    |> Enum.flat_map(fn room_id ->
      case Room.info(room_id) do
        {:ok, room} -> [room]
        {:error, :not_found} -> []
      end
    end)
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  @spec find_owner_room(String.t(), String.t()) :: Room.t() | nil
  def find_owner_room(guild_id, owner_id) do
    Registry.select(Botchini.Screens.Registry, [
      {{:"$1", :_, {guild_id, owner_id}}, [], [:"$1"]}
    ])
    |> Enum.find_value(&get_room/1)
  end

  @spec create_stream_key(%{
          guild_id: String.t(),
          owner_id: String.t(),
          channel_id: String.t(),
          owner_name: String.t()
        }) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def create_stream_key(attrs) do
    key = random_id()

    %StreamKey{}
    |> StreamKey.changeset(%{
      discord_guild_id: attrs.guild_id,
      discord_user_id: attrs.owner_id,
      discord_channel_id: attrs.channel_id,
      owner_name: attrs.owner_name,
      key_hash: hash_key(key)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:discord_channel_id, :owner_name, :key_hash, :updated_at]},
      conflict_target: [:discord_guild_id, :discord_user_id]
    )
    |> case do
      {:ok, _stream_key} -> {:ok, key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec get_stream_key(String.t()) :: StreamKey.t() | nil
  def get_stream_key(key) when is_binary(key), do: Repo.get_by(StreamKey, key_hash: hash_key(key))

  @spec start_stream_key_room(StreamKey.t()) :: {:ok, Room.t()} | {:error, term()}
  def start_stream_key_room(%StreamKey{} = stream_key) do
    start_room(%{
      title: Room.default_title(stream_key.owner_name, :obs),
      guild_id: stream_key.discord_guild_id,
      channel_id: stream_key.discord_channel_id,
      owner_id: stream_key.discord_user_id,
      owner_name: stream_key.owner_name
    })
  end

  defp hash_key(key), do: :crypto.hash(:sha256, key)

  @spec list_stream_channels() :: [StreamChannel.t()]
  def list_stream_channels, do: Repo.all(StreamChannel)

  @spec get_stream_channel(String.t()) :: StreamChannel.t() | nil
  def get_stream_channel(guild_id), do: Repo.get_by(StreamChannel, discord_guild_id: guild_id)

  @doc """
  Sets the guild's streams channel and the message listing its screen shares there
  """
  @spec put_stream_channel(String.t(), String.t(), String.t()) ::
          {:ok, StreamChannel.t()} | {:error, Ecto.Changeset.t()}
  def put_stream_channel(guild_id, channel_id, message_id) do
    %StreamChannel{}
    |> StreamChannel.changeset(%{
      discord_guild_id: guild_id,
      discord_channel_id: channel_id,
      discord_message_id: message_id
    })
    |> Repo.insert(
      on_conflict: {:replace, [:discord_channel_id, :discord_message_id, :updated_at]},
      conflict_target: :discord_guild_id,
      returning: true
    )
  end

  @doc """
  How the guild's admins set up its page, or the defaults if they never did
  """
  @spec get_settings(String.t()) :: ScreenSettings.t()
  def get_settings(guild_id) do
    Repo.get_by(ScreenSettings, discord_guild_id: guild_id) ||
      %ScreenSettings{discord_guild_id: guild_id}
  end

  @doc """
  Changes which ads the guild's page shows, for everyone on it right away.
  `ad_id` is only kept for the `:fixed` mode
  """
  @spec set_ads(String.t(), ScreenSettings.ads_mode(), String.t() | nil) ::
          {:ok, ScreenSettings.t()} | {:error, Ecto.Changeset.t()}
  def set_ads(guild_id, mode, ad_id \\ nil) do
    %ScreenSettings{}
    |> ScreenSettings.changeset(%{discord_guild_id: guild_id, ads_mode: mode, ad_id: ad_id})
    |> Repo.insert(
      on_conflict: {:replace, [:ads_mode, :ad_id, :updated_at]},
      conflict_target: :discord_guild_id,
      returning: true
    )
    |> tap(fn
      {:ok, settings} ->
        Phoenix.PubSub.broadcast(Botchini.PubSub, guild_topic(guild_id), {:screen_ads, settings})

      {:error, _changeset} ->
        :ok
    end)
  end

  @spec stop_room(Room.t(), atom()) :: :ok | {:error, :not_found}
  def stop_room(%Room{} = room, reason \\ :stopped), do: Room.stop(room.id, reason)

  @doc """
  Subscribes to every room's `:live` and `:ended` events, or to all events of a single room
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Botchini.PubSub, @topic)

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(room_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, room_topic(room_id))

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(room_id), do: Phoenix.PubSub.unsubscribe(Botchini.PubSub, room_topic(room_id))

  @spec subscribe_guild(String.t()) :: :ok | {:error, term()}
  def subscribe_guild(guild_id),
    do: Phoenix.PubSub.subscribe(Botchini.PubSub, guild_topic(guild_id))

  @doc """
  Lists the members with the guild's page open. The page gets a `presence_diff`
  broadcast whenever the list changes, once it called `subscribe_online/1`
  """
  @spec list_online(String.t()) :: [%{id: String.t(), name: String.t(), admin?: boolean()}]
  def list_online(guild_id) do
    guild_id
    |> Presence.topic()
    |> Presence.list()
    |> Enum.map(fn {user_id, %{metas: [meta | _] = metas}} ->
      %{id: user_id, name: meta.name, admin?: Enum.any?(metas, & &1.admin?)}
    end)
    |> Enum.sort_by(&{String.downcase(&1.name), &1.id})
  end

  @spec subscribe_online(String.t()) :: :ok | {:error, term()}
  def subscribe_online(guild_id),
    do: Phoenix.PubSub.subscribe(Botchini.PubSub, Presence.topic(guild_id))

  @doc """
  Marks the member as online in the guild for as long as the calling process lives.
  Whether they're an admin is checked when they open the page, and kept until they leave
  """
  @spec track_online(String.t(), %{id: String.t(), name: String.t()}, boolean()) :: :ok
  def track_online(guild_id, %{id: user_id, name: name}, admin?) do
    {:ok, _ref} =
      Presence.track(self(), Presence.topic(guild_id), user_id, %{name: name, admin?: admin?})

    :ok
  end

  @doc false
  @spec broadcast(Room.t(), :live | :updated | :ended) :: :ok
  def broadcast(%Room{} = room, event) do
    message = {:screen_room, event, room}

    if event in [:live, :ended], do: Phoenix.PubSub.broadcast(Botchini.PubSub, @topic, message)
    Phoenix.PubSub.broadcast(Botchini.PubSub, guild_topic(room.guild_id), message)
    Phoenix.PubSub.broadcast(Botchini.PubSub, room_topic(room.id), message)
  end

  defp room_topic(room_id), do: "#{@topic}:#{room_id}"
  defp guild_topic(guild_id), do: "#{@topic}:guild:#{guild_id}"

  # 128 bits of randomness, so links can't be guessed or enumerated
  defp random_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
