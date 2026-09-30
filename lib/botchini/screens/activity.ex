defmodule Botchini.Screens.Activity do
  @moduledoc """
  What happened lately on a guild's screen sharing pages, for the members to check
  what they missed: who came and went, which sounds were played, who started or
  stopped streaming, and what members said in the chat. Only the last few events
  of each guild are kept, in memory.

  Pages get `{:screen_activity, event}` messages once they subscribe.
  """

  use GenServer

  alias Botchini.Screens

  @max_events 100
  @max_message_length 300

  # Members can send a few messages in a row, then have to wait
  @burst 5
  @burst_window_ms 10_000

  @type kind ::
          :joined | :left | :sound | :sound_stopped | :stream_started | :stream_ended | :message

  @typedoc """
  `actor_id` is only known for messages, for the pages to tell who wrote them
  """
  @type event :: %{
          id: pos_integer(),
          at: DateTime.t(),
          kind: kind(),
          actor: String.t(),
          actor_id: String.t() | nil,
          detail: String.t() | nil
        }

  @type limiter :: [integer()]

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Adds an event to the guild's activity. `detail` says more about it, like the
  sound that was played
  """
  @spec record(String.t(), kind(), String.t(), String.t() | nil) :: :ok
  def record(guild_id, kind, actor, detail \\ nil),
    do: GenServer.cast(__MODULE__, {:record, guild_id, new_event(kind, actor, detail)})

  @doc """
  Adds a chat message from `user`. Blank messages are dropped and long ones cut
  short, and line breaks become spaces as messages are shown on a single line
  """
  @spec say(String.t(), %{id: String.t(), name: String.t()}, String.t()) :: :ok | :blank
  def say(guild_id, %{id: user_id, name: name}, text) when is_binary(text) do
    case clean_message(text) do
      "" ->
        :blank

      text ->
        GenServer.cast(__MODULE__, {:record, guild_id, new_event(:message, name, text, user_id)})
    end
  end

  defp clean_message(text) do
    text
    |> String.replace(~r/[[:cntrl:]]+/u, " ")
    |> String.trim()
    |> String.slice(0, @max_message_length)
  end

  @spec max_message_length() :: pos_integer()
  def max_message_length, do: @max_message_length

  @spec new_limiter() :: limiter()
  def new_limiter, do: []

  @doc """
  Counts a message sent at `now` (in milliseconds), unless the member sent too
  many in the last few seconds
  """
  @spec hit(limiter(), integer()) :: {:ok, limiter()} | :limited
  def hit(limiter, now) do
    recent = Enum.filter(limiter, &(now - &1 < @burst_window_ms))
    if length(recent) >= @burst, do: :limited, else: {:ok, [now | recent]}
  end

  @doc """
  The guild's latest events, newest first
  """
  @spec list(String.t()) :: [event()]
  def list(guild_id), do: GenServer.call(__MODULE__, {:list, guild_id})

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(guild_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, topic(guild_id))

  @doc """
  Turns a change of the guild's online members into events. Someone only counts as
  joined with their first tab and as left with their last one, and leaving is only
  reported when they don't come back right away: reloading the page is not leaving
  """
  @spec presence_changed(String.t(), %{joins: map(), leaves: map()}, map()) :: :ok
  def presence_changed(guild_id, %{joins: joins, leaves: leaves}, presences) do
    joined =
      for {key, presence} <- joins, all_new?(presence, presences[key]), do: named(key, presence)

    left = for {key, presence} <- leaves, not is_map_key(presences, key), do: named(key, presence)

    if joined != [] or left != [],
      do: GenServer.cast(__MODULE__, {:presence, guild_id, joined, left})

    :ok
  end

  @doc false
  @spec clear(String.t()) :: :ok
  def clear(guild_id), do: GenServer.call(__MODULE__, {:clear, guild_id})

  defp all_new?(%{metas: joined}, current), do: length(joined) == count(current)

  defp count(nil), do: 0
  defp count(%{metas: metas}), do: length(metas)
  defp count(metas) when is_list(metas), do: length(metas)

  defp named(key, %{metas: [%{name: name} | _]}), do: {key, name}

  defp new_event(kind, actor, detail, actor_id \\ nil) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      at: DateTime.utc_now(),
      kind: kind,
      actor: actor,
      actor_id: actor_id,
      detail: detail
    }
  end

  defp topic(guild_id), do: "screens:activity:#{guild_id}"

  ## Callbacks

  @impl true
  def init(_arg) do
    # Events per guild, newest first, and the leaves waiting to be confirmed
    {:ok, %{events: %{}, pending_leaves: %{}}}
  end

  @impl true
  def handle_call({:list, guild_id}, _from, state),
    do: {:reply, Map.get(state.events, guild_id, []), state}

  def handle_call({:clear, guild_id}, _from, state),
    do: {:reply, :ok, %{state | events: Map.delete(state.events, guild_id)}}

  @impl true
  def handle_cast({:record, guild_id, event}, state),
    do: {:noreply, put_event(state, guild_id, event)}

  def handle_cast({:presence, guild_id, joined, left}, state) do
    state = Enum.reduce(left, state, &wait_for_return(&2, guild_id, &1))
    {:noreply, Enum.reduce(joined, state, &join(&2, guild_id, &1))}
  end

  @impl true
  def handle_info({:confirm_leave, guild_id, user_id}, state) do
    case Map.pop(state.pending_leaves, {guild_id, user_id}) do
      {nil, _pending} ->
        {:noreply, state}

      {event, pending} ->
        {:noreply, put_event(%{state | pending_leaves: pending}, guild_id, event)}
    end
  end

  # Cancelling a timer doesn't remove the message it already sent, which finds
  # nothing pending anymore
  defp wait_for_return(state, guild_id, {user_id, name}) do
    key = {guild_id, user_id}

    if is_map_key(state.pending_leaves, key) do
      state
    else
      grace_ms = Screens.config()[:activity_leave_grace_ms]
      Process.send_after(self(), {:confirm_leave, guild_id, user_id}, grace_ms)

      put_in(state, [:pending_leaves, key], new_event(:left, name, nil))
    end
  end

  # Someone coming back before their leave was reported never left
  defp join(state, guild_id, {user_id, name}) do
    case Map.pop(state.pending_leaves, {guild_id, user_id}) do
      {nil, _pending} ->
        put_event(state, guild_id, new_event(:joined, name, nil))

      {_left, pending} ->
        %{state | pending_leaves: pending}
    end
  end

  defp put_event(state, guild_id, event) do
    Phoenix.PubSub.broadcast(Botchini.PubSub, topic(guild_id), {:screen_activity, event})

    update_in(state, [:events, Access.key(guild_id, [])], &Enum.take([event | &1], @max_events))
  end
end
