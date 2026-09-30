defmodule Botchini.Screens.Pointers do
  @moduledoc """
  Pointers members show each other on a guild's screen sharing pages, which draw
  a trail while the mouse button is held. Shapes drawn can set off special effects.

  Browsers send their pointer's latest positions in small batches, relative to
  what it was over: a screen share, so it lands on the same spot of the stream for
  everyone, or the page. Everything browsers send is checked here, as it's relayed
  to the other pages of the guild as is
  """

  @topic "screens:pointers"

  @styles ~w(matte glossy neon sparkle rainbow pixel comet)
  @effects ~w(lightning star heart circle spiral target infinity)
  @colors 0..9
  @widths 4..24

  # Positions over a screen share are fractions of it, and over the page fractions
  # of its width, so pages taller than they're wide go well past 1
  @stream_range {-1, 2}
  @page_x_range {-1, 2}
  @page_y_range {-1, 50}

  @max_points 40
  @max_anchor_id 100

  # Browsers send about 20 batches a second, the rest is room for hiccups
  @moves_per_second 40
  @effect_interval_ms 1_500

  @type anchor :: %{k: String.t(), i: String.t()}
  @type move :: %{
          a: anchor(),
          p: [[number()]],
          c: non_neg_integer(),
          st: String.t(),
          w: pos_integer()
        }
  @type effect :: %{e: String.t(), a: anchor(), x: number(), y: number()}

  @spec styles() :: [String.t()]
  def styles, do: @styles

  @spec effects() :: [String.t()]
  def effects, do: @effects

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(guild_id), do: Phoenix.PubSub.subscribe(Botchini.PubSub, topic(guild_id))

  @doc """
  Relays a message to the guild's other pages, without echoing it back to the caller
  """
  @spec broadcast(String.t(), term()) :: :ok | {:error, term()}
  def broadcast(guild_id, message),
    do:
      Phoenix.PubSub.broadcast_from(
        Botchini.PubSub,
        self(),
        topic(guild_id),
        {:pointers, message}
      )

  defp topic(guild_id), do: "#{@topic}:#{guild_id}"

  @doc """
  Checks a batch of pointer positions as `[x, y, time, held]`, with the pointer's look
  """
  @spec parse_move(map()) :: {:ok, move()} | :error
  def parse_move(%{"a" => anchor, "p" => points, "c" => color, "st" => style, "w" => width})
      when is_list(points) and length(points) in 1..@max_points and color in @colors and
             style in @styles and width in @widths do
    with {:ok, anchor} <- parse_anchor(anchor),
         true <- Enum.all?(points, &valid_point?(anchor, &1)) do
      {:ok, %{a: anchor, p: points, c: color, st: style, w: width}}
    else
      _invalid -> :error
    end
  end

  def parse_move(_params), do: :error

  @spec parse_effect(map()) :: {:ok, effect()} | :error
  def parse_effect(%{"e" => effect, "a" => anchor, "x" => x, "y" => y})
      when effect in @effects do
    with {:ok, anchor} <- parse_anchor(anchor),
         true <- valid_position?(anchor, x, y) do
      {:ok, %{e: effect, a: anchor, x: x, y: y}}
    else
      _invalid -> :error
    end
  end

  def parse_effect(_params), do: :error

  defp parse_anchor(%{"k" => kind, "i" => id})
       when kind in ["s", "p"] and is_binary(id) and byte_size(id) in 1..@max_anchor_id,
       do: {:ok, %{k: kind, i: id}}

  defp parse_anchor(_anchor), do: :error

  defp valid_point?(anchor, [x, y, time, held])
       when is_integer(time) and time >= 0 and held in [0, 1],
       do: valid_position?(anchor, x, y)

  defp valid_point?(_anchor, _point), do: false

  defp valid_position?(%{k: "s"}, x, y),
    do: within?(x, @stream_range) and within?(y, @stream_range)

  defp valid_position?(%{k: "p"}, x, y),
    do: within?(x, @page_x_range) and within?(y, @page_y_range)

  defp within?(value, {min, max}) when is_number(value), do: value >= min and value <= max
  defp within?(_value, _range), do: false

  @typedoc """
  When a page last sent positions, how many it sent in that second, and its last effect
  """
  @type limiter :: %{
          second: integer() | nil,
          moves: non_neg_integer(),
          effect_at: integer() | nil
        }

  @spec new_limiter() :: limiter()
  def new_limiter, do: %{second: nil, moves: 0, effect_at: nil}

  @doc """
  Counts a batch of positions sent at `now` (in milliseconds), refusing them once a
  page sends more than it should, so one can't flood the others
  """
  @spec hit_move(limiter(), integer()) :: {:ok, limiter()} | :limited
  def hit_move(limiter, now) do
    second = div(now, 1_000)

    cond do
      limiter.second != second -> {:ok, %{limiter | second: second, moves: 1}}
      limiter.moves < @moves_per_second -> {:ok, %{limiter | moves: limiter.moves + 1}}
      true -> :limited
    end
  end

  @spec hit_effect(limiter(), integer()) :: {:ok, limiter()} | :limited
  def hit_effect(%{effect_at: effect_at}, now)
      when is_integer(effect_at) and now - effect_at < @effect_interval_ms,
      do: :limited

  def hit_effect(limiter, now), do: {:ok, %{limiter | effect_at: now}}
end
