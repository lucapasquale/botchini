defmodule Botchini.Screens do
  @moduledoc """
  Screen sharing rooms, where a member broadcasts their screen from the browser
  to the other members watching it. Rooms only live in memory, and each one gets
  unguessable ids that stop working once it ends
  """

  alias Botchini.Screens.{Room, RoomSupervisor}

  @topic "screens"

  @defaults [
    ice_servers: [],
    ice_port_range: nil,
    announced_ip: nil,
    max_viewers: 20,
    # How long the broadcaster has to open their link after creating the room
    start_timeout_ms: :timer.minutes(10),
    # How long the room waits for the broadcaster to come back after disconnecting
    reconnect_timeout_ms: :timer.minutes(2),
    max_duration_ms: :timer.hours(12)
  ]

  @spec config() :: Keyword.t()
  def config do
    Keyword.merge(@defaults, Application.get_env(:botchini, __MODULE__, []))
  end

  @type start_attrs :: %{
          title: String.t(),
          guild_id: String.t(),
          channel_id: String.t(),
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
          struct!(Room, Map.merge(attrs, %{id: random_id(), broadcast_key: random_id()}))

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

  @doc """
  Gets the room the broadcast key belongs to, without leaking through timing
  whether the room exists but the key is wrong
  """
  @spec get_room_for_broadcast(String.t(), String.t()) :: Room.t() | nil
  def get_room_for_broadcast(room_id, broadcast_key)
      when is_binary(room_id) and is_binary(broadcast_key) do
    with %Room{} = room <- get_room(room_id),
         true <- Plug.Crypto.secure_compare(room.broadcast_key, broadcast_key) do
      room
    else
      _ -> nil
    end
  end

  def get_room_for_broadcast(_room_id, _broadcast_key), do: nil

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

  @spec stop_room(Room.t(), atom()) :: :ok | {:error, :not_found}
  def stop_room(%Room{} = room, reason \\ :stopped), do: Room.stop(room.id, reason)

  @doc """
  Subscribes to every room's `:live` and `:ended` events, or to all events of a single room
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(Botchini.PubSub, @topic)

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(room_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, room_topic(room_id))

  @doc false
  @spec broadcast(Room.t(), :live | :updated | :ended) :: :ok
  def broadcast(%Room{} = room, event) do
    message = {:screen_room, event, room}

    if event in [:live, :ended], do: Phoenix.PubSub.broadcast(Botchini.PubSub, @topic, message)
    Phoenix.PubSub.broadcast(Botchini.PubSub, room_topic(room.id), message)
  end

  @doc """
  Tells the room's pages that its watch link couldn't be posted on Discord
  """
  @spec broadcast_announcement_failed(Room.t()) :: :ok
  def broadcast_announcement_failed(%Room{} = room) do
    Phoenix.PubSub.broadcast(
      Botchini.PubSub,
      room_topic(room.id),
      {:screen_announcement_failed, room.id}
    )
  end

  defp room_topic(room_id), do: "#{@topic}:#{room_id}"

  # 128 bits of randomness, so links can't be guessed or enumerated
  defp random_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
end
