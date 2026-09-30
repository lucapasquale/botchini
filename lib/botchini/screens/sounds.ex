defmodule Botchini.Screens.Sounds do
  @moduledoc """
  Soundboard of the screen sharing pages. Anyone on a guild's pages can play a
  sound, and everyone else on them hears it, one sound at a time. The files live
  in priv/static/sounds
  """

  @topic "screens:sounds"

  @type sound :: %{id: String.t(), name: String.t(), emoji: String.t(), file: String.t()}

  @sounds [
    %{id: "volibero", name: "Volibero", emoji: "🐻", file: "volibero.mp3"},
    %{id: "volibear-mix", name: "Volibear", emoji: "⚡", file: "volibear-mix.mp3"},
    %{
      id: "volibear-morrendo",
      name: "Volibear morrendo",
      emoji: "💀",
      file: "volibear-morrendo.mp3"
    },
    %{id: "volibear-dying", name: "Volibear dying", emoji: "⚰️", file: "volibear-dying.mp3"},
    %{id: "oh-verstappen", name: "Oh Verstappen", emoji: "🏎️", file: "oh-verstappen.mp3"},
    %{id: "tu-tu-tu-du", name: "Tu tu tu du", emoji: "🏁", file: "tu-tu-tu-du.mp3"},
    %{id: "max-dododo", name: "Max dododo", emoji: "🎶", file: "max-dododo.mp3"},
    %{id: "cowboy-bob", name: "Cowboy Bob", emoji: "🤠", file: "cowboy-bob.mp3"},
    %{id: "ilarie", name: "Ilariê", emoji: "👑", file: "ilarie.mp3"},
    %{id: "scooby-doo", name: "Scooby-Doo", emoji: "🐶", file: "scooby-doo.mp3"},
    %{id: "arnold-informer", name: "Arnold Informer", emoji: "💪", file: "arnold-informer.mp3"},
    %{id: "careless-whisper", name: "Careless Whisper", emoji: "🎷", file: "careless-whisper.mp3"},
    %{id: "a-thousand-miles", name: "A Thousand Miles", emoji: "🎹", file: "a-thousand-miles.mp3"},
    %{
      id: "arnold-spiderman",
      name: "Arnold Spider-Man",
      emoji: "🕷️",
      file: "arnold-spiderman.mp3"
    },
    %{id: "poeta-bolsonaro", name: "Poeta Bolsonaro", emoji: "📜", file: "poeta-bolsonaro.mp3"},
    %{id: "eae", name: "Eaê", emoji: "🗣️", file: "eae.mp3"},
    %{id: "mj", name: "MJ", emoji: "🕺", file: "mj.mp3"},
    %{id: "hello-michael", name: "Hello Michael", emoji: "👋", file: "hello-michael.mp3"},
    %{id: "diddy-ligou", name: "Diddy ligou", emoji: "📞", file: "diddy-ligou.mp3"},
    %{id: "mj-grunts", name: "MJ grunts", emoji: "😤", file: "mj-grunts.mp3"},
    %{id: "sem-nada", name: "Sem Nada", emoji: "🔥", file: "sem-nada.mp3"},
    %{id: "brasil-com-s", name: "Brasil com S", emoji: "🦜", file: "brasil-com-s.mp3"},
    %{id: "vem-no-pique", name: "Vem no Pique", emoji: "💃", file: "vem-no-pique.mp3"},
    %{id: "all-my-fellas", name: "All My Fellas", emoji: "👬", file: "all-my-fellas.mp3"},
    %{id: "lukeba", name: "Lukeba da Madeira", emoji: "🪵", file: "lukeba.mp3"},
    %{id: "cabecoide", name: "Cabeçoide", emoji: "🧠", file: "cabecoide.mp3"}
  ]

  # Playing this many sounds within the window makes the member wait a bit
  @burst 3
  @burst_window_ms 3_000
  @cooldown_ms 5_000

  @spec all() :: [sound()]
  def all, do: @sounds

  @spec get(String.t()) :: sound() | nil
  def get(id), do: Enum.find(@sounds, &(&1.id == id))

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(guild_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, topic(guild_id))

  @doc """
  Plays the sound on the guild's pages, cutting off the one playing there. Pages
  are told who played it, so members who muted them don't hear it
  """
  @spec play(String.t(), sound(), String.t()) :: :ok
  def play(guild_id, sound, user_id) do
    Phoenix.PubSub.broadcast(
      Botchini.PubSub,
      topic(guild_id),
      {:soundboard, {:play, sound, user_id}}
    )
  end

  @doc """
  Stops the sound playing on the guild's pages
  """
  @spec stop(String.t()) :: :ok
  def stop(guild_id),
    do: Phoenix.PubSub.broadcast(Botchini.PubSub, topic(guild_id), {:soundboard, :stop})

  defp topic(guild_id), do: "#{@topic}:#{guild_id}"

  @typedoc """
  When a member played their latest sounds, and until when they're cooling down
  """
  @type limiter :: %{played_at: [integer()], cooldown_until: integer() | nil}

  @spec new_limiter() :: limiter()
  def new_limiter, do: %{played_at: [], cooldown_until: nil}

  @doc """
  Counts a sound played at `now` (in milliseconds), or tells how long until the
  member can play again. Playing too many sounds too fast starts a cooldown right
  after the last one
  """
  @spec hit(limiter(), integer()) :: {:ok, limiter()} | {:cooldown, pos_integer()}
  def hit(limiter, now) do
    case cooldown_left(limiter, now) do
      0 ->
        played_at = [now | Enum.filter(limiter.played_at, &(now - &1 < @burst_window_ms))]

        if length(played_at) >= @burst,
          do: {:ok, %{played_at: [], cooldown_until: now + @cooldown_ms}},
          else: {:ok, %{played_at: played_at, cooldown_until: nil}}

      left_ms ->
        {:cooldown, left_ms}
    end
  end

  @doc """
  How long until the member can play sounds again, 0 when they can already
  """
  @spec cooldown_left(limiter(), integer()) :: non_neg_integer()
  def cooldown_left(%{cooldown_until: until}, now) when is_integer(until), do: max(until - now, 0)
  def cooldown_left(_limiter, _now), do: 0
end
