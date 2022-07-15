defmodule Botchini.Twitch do
  @moduledoc """
  Handles twitch context
  """

  import Ecto.Query
  alias Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo
  alias Botchini.Twitch.API
  alias Botchini.Twitch.API.Structs
  alias Botchini.Twitch.Schema.{Follower, Stream}

  @spec count_streams() :: Integer.t()
  def count_streams() do
    Query.from(s in Stream, select: count())
    |> Repo.one!()
  end

  @spec find_stream_by_twitch_user_id(String.t()) :: nil | Stream.t()
  def find_stream_by_twitch_user_id(twitch_user_id) do
    Repo.get_by(Stream, twitch_user_id: twitch_user_id)
  end

  @spec find_followers_for_stream(Stream.t()) :: [Follower.t()]
  def find_followers_for_stream(stream) do
    Follower
    |> Ecto.Query.where(stream_id: ^stream.id)
    |> Repo.all()
  end

  @spec search_twitch_streams(String.t()) :: [{String.t(), String.t()}]
  def search_twitch_streams(term) do
    if String.length(term) <= 2 do
      API.top_live_streams()
      |> Enum.map(fn stream -> {stream.user_login, stream.user_name} end)
    else
      API.search_channels(term)
      |> Enum.map(fn channel -> {channel.broadcaster_login, channel.display_name} end)
    end
  end

  @spec search_following_streams(String.t(), %{channel_id: String.t()}) :: [Stream.t()]
  def search_following_streams(term, %{channel_id: channel_id}) do
    term = "%#{term}%"

    from(
      s in Stream,
      join: sf in Follower,
      on: sf.stream_id == s.id,
      where: ilike(s.code, ^term),
      where: sf.discord_channel_id == ^channel_id,
      limit: 5
    )
    |> Repo.all()
  end

  @spec follow_stream(String.t(), Guild.t() | nil, %{
          channel_id: String.t(),
          user_id: String.t() | nil
        }) ::
          {:ok, Stream.t()} | {:error, :invalid_stream} | {:error, :already_following}
  def follow_stream(code, guild, follower_info) do
    case upsert_stream(code) do
      {:error, _} ->
        {:error, :invalid_stream}

      {:ok, stream} ->
        existing_follower =
          Repo.get_by(Follower,
            stream_id: stream.id,
            discord_channel_id: follower_info.channel_id
          )

        case existing_follower do
          nil ->
            insert_follower(stream, guild, follower_info)
            {:ok, stream}

          _follower ->
            {:error, :already_following}
        end
    end
  end

  @spec unfollow(String.t(), %{channel_id: String.t()}) :: {:ok} | {:error, :not_found}
  def unfollow(code, %{channel_id: channel_id}) do
    case Repo.get_by(Stream, code: code) do
      nil ->
        {:error, :not_found}

      stream ->
        existing_follower =
          Repo.get_by(Follower,
            stream_id: stream.id,
            discord_channel_id: channel_id
          )

        case existing_follower do
          nil ->
            {:error, :not_found}

          follower ->
            unfollow_stream(stream, follower)
            {:ok}
        end
    end
  end

  @spec guild_following_list(Guild.t()) :: {:ok, [{String.t(), String.t()}]}
  def guild_following_list(guild) do
    follow_list =
      from(
        s in Stream,
        join: sf in Follower,
        on: sf.stream_id == s.id,
        where: sf.guild_id == ^guild.id,
        select: {sf.discord_channel_id, s.code}
      )
      |> Repo.all()

    {:ok, follow_list}
  end

  @spec channel_following_list(String.t()) :: {:ok, [String.t()]}
  def channel_following_list(channel_id) do
    follow_list =
      from(
        s in Stream,
        join: sf in Follower,
        on: sf.stream_id == s.id,
        where: sf.discord_channel_id == ^channel_id,
        select: s.code
      )
      |> Repo.all()

    {:ok, follow_list}
  end

  @spec channel_follower(String.t(), %{channel_id: String.t()}) ::
          {:error, :not_found} | {:ok, Follower.t()}
  def channel_follower(code, %{channel_id: channel_id}) do
    case Repo.get_by(Stream, code: code) do
      nil ->
        {:error, :not_found}

      stream ->
        case Repo.get_by(Follower, stream_id: stream.id, discord_channel_id: channel_id) do
          nil ->
            {:error, :not_found}

          follower ->
            {:ok, follower}
        end
    end
  end

  @spec stream_info(String.t()) ::
          {:error, :not_found} | {:ok, {Structs.User.t(), Structs.Stream.t() | nil}}
  def stream_info(code) do
    case API.get_user(code) do
      nil ->
        {:error, :not_found}

      user ->
        {:ok, {user, API.get_stream(code)}}
    end
  end

  defp upsert_stream(code) do
    case Repo.get_by(Stream, code: code) do
      %Stream{} = existing ->
        {:ok, existing}

      nil ->
        case API.get_user(code) do
          nil ->
            {:error, :invalid_stream}

          user ->
            event_subscription = API.add_stream_webhook(user.id)

            %Stream{}
            |> Stream.changeset(%{
              code: code,
              name: user.display_name,
              twitch_user_id: user.id,
              twitch_subscription_id: event_subscription["id"]
            })
            |> Repo.insert()
        end
    end
  end

  defp insert_follower(stream, guild, %{channel_id: channel_id, user_id: user_id}) do
    %Follower{}
    |> Follower.changeset(%{
      stream_id: stream.id,
      guild_id: guild && guild.id,
      discord_user_id: user_id,
      discord_channel_id: channel_id
    })
    |> Repo.insert!()
  end

  defp unfollow_stream(stream, follower) do
    Repo.delete(follower)

    remaining_followers =
      Ecto.Query.where(Follower, stream_id: ^stream.id)
      |> Repo.all()

    if remaining_followers == [] do
      API.delete_stream_webhook(stream.twitch_subscription_id)
      Repo.delete(stream)
    end
  end
end
