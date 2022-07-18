defmodule Botchini.Creators do
  @moduledoc """
  Handles creators context
  """

  import Ecto.Query
  alias Ecto.Query

  alias Botchini.Creators.Clients.{Twitch, Youtube}
  alias Botchini.Creators.Schema.{Creator, Follower}
  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo

  @type creator_input :: {Creator.services(), String.t()}

  @spec count_creators() :: Integer.t()
  def count_creators do
    Query.from(s in Creator, select: count())
    |> Repo.one!()
  end

  @spec find_creator_by_twitch_user_id(String.t()) :: nil | Creator.t()
  def find_creator_by_twitch_user_id(twitch_user_id) do
    from(c in Creator,
      where: c.service == :twitch,
      where: c.service_id == ^twitch_user_id
    )
    |> Repo.one()
  end

  @spec find_creator_by_youtube_channel_id(String.t()) :: nil | Creator.t()
  def find_creator_by_youtube_channel_id(channel_id) do
    from(c in Creator,
      where: c.service == :youtube,
      where: c.service_id == ^channel_id
    )
    |> Repo.one()
  end

  @spec find_followers_for_creator(Creator.t()) :: [Follower.t()]
  def find_followers_for_creator(creator) do
    Follower
    |> Ecto.Query.where(creator_id: ^creator.id)
    |> Repo.all()
  end

  @spec search_following_creators({Creator.services(), String.t()}, %{channel_id: String.t()}) ::
          list({String.t(), String.t()})
  def search_following_creators({service, term}, %{channel_id: channel_id}) do
    term = "%#{term}%"

    from(
      c in Creator,
      join: f in Follower,
      on: f.creator_id == c.id,
      select: {c.id, c.name},
      where: c.service == ^service,
      where: ilike(c.code, ^term),
      where: f.discord_channel_id == ^channel_id,
      limit: 5
    )
    |> Repo.all()
  end

  @spec follow_creator(Creator.t(), Guild.t() | nil, %{
          channel_id: String.t(),
          user_id: String.t() | nil
        }) ::
          {:ok, Follower.t()} | {:error, :already_following}
  def follow_creator(creator, guild, follower_info) do
    existing_follower =
      Repo.get_by(Follower,
        creator_id: creator.id,
        discord_channel_id: follower_info.channel_id
      )

    case existing_follower do
      nil ->
        follower =
          Follower.changeset(%Follower{}, %{
            creator_id: creator.id,
            guild_id: guild && guild.id,
            discord_user_id: follower_info.user_id,
            discord_channel_id: follower_info.channel_id
          })
          |> Repo.insert()

        {:ok, follower}

      _follower ->
        {:error, :already_following}
    end
  end

  @spec unfollow(integer(), %{channel_id: String.t()}) ::
          {:error, :not_found} | {:ok, Creator.t()}
  def unfollow(creator_id, %{channel_id: channel_id}) do
    case Repo.get(Creator, creator_id) do
      nil ->
        {:error, :not_found}

      creator ->
        case Repo.get_by(Follower, creator_id: creator.id, discord_channel_id: channel_id) do
          nil ->
            {:error, :not_found}

          follower ->
            Repo.delete(follower)
            {:ok, creator}
        end
    end
  end

  @spec guild_following_list(Guild.t()) :: {:ok, [{String.t(), String.t()}]}
  def guild_following_list(guild) do
    follow_list =
      from(
        c in Creator,
        join: f in Follower,
        on: f.creator_id == c.id,
        where: f.guild_id == ^guild.id,
        select: {f.discord_channel_id, c.code}
      )
      |> Repo.all()

    {:ok, follow_list}
  end

  @spec channel_following_list(String.t()) :: {:ok, [String.t()]}
  def channel_following_list(channel_id) do
    follow_list =
      from(
        c in Creator,
        join: f in Follower,
        on: f.creator_id == c.id,
        where: f.discord_channel_id == ^channel_id,
        select: c.code
      )
      |> Repo.all()

    {:ok, follow_list}
  end

  @spec discord_channel_follower(integer(), %{channel_id: String.t()}) ::
          {:error, :not_found} | {:ok, Follower.t()}
  def discord_channel_follower(creator_id, %{channel_id: channel_id}) do
    case Repo.get_by(Follower, creator_id: creator_id, discord_channel_id: channel_id) do
      nil ->
        {:error, :not_found}

      follower ->
        {:ok, follower}
    end
  end

  @spec stream_info(String.t()) ::
          {:error, :not_found} | {:ok, {Twitch.Structs.User.t(), Twitch.Structs.Stream.t() | nil}}
  def stream_info(code) do
    case Twitch.get_user(code) do
      nil -> {:error, :not_found}
      user -> {:ok, {user, Twitch.get_stream(code)}}
    end
  end

  @spec twitch_user_info(String.t()) :: Twitch.Structs.User.t()
  def twitch_user_info(user_id) do
    Twitch.get_user(user_id)
  end

  @spec youtube_video_info(String.t(), String.t()) ::
          {:error, :not_found} | {:ok, {Youtube.Structs.Channel.t(), Youtube.Structs.Video.t()}}
  def youtube_video_info(channel_id, video_id) do
    case Youtube.get_channel_by_id(channel_id) do
      nil ->
        {:error, :not_found}

      channel ->
        video = Youtube.get_video(video_id)
        {:ok, {channel, video}}
    end
  end

  @spec youtube_channel_info(String.t()) :: Youtube.Structs.Channel.t() | nil
  def youtube_channel_info(channel_id) do
    Youtube.get_channel_by_id(channel_id)
  end

  @spec search_youtube_channels(String.t()) ::
          {:error, :not_found} | {:ok, nonempty_list(Youtube.Structs.Channel.t())}
  def search_youtube_channels(term) do
    case Youtube.search_channels(term) do
      channels when channels == [] -> {:error, :not_found}
      channels -> {:ok, channels}
    end
  end

  @spec upsert_creator(Creator.services(), String.t()) ::
          {:error, :invalid_creator} | {:ok, Creator.t()}
  def upsert_creator(service, term) do
    case search_channel(service, term) do
      {:error, _} ->
        {:error, :invalid_creator}

      {:ok, {service_id, name}} ->
        case Repo.get_by(Creator, service: service, service_id: service_id) do
          %Creator{} = existing ->
            {:ok, existing}

          nil ->
            webhook_id = subscribe_to_service(service, service_id)

            Creator.changeset(%Creator{}, %{
              service: service,
              name: name,
              service_id: service_id,
              webhook_id: webhook_id,
              # TODO: remove
              code: name,
              metadata: %{}
            })
            |> Repo.insert()
        end
    end
  end

  defp search_channel(:twitch, term) do
    case Twitch.search_channels(term) do
      channels when channels == [] ->
        {:error, :not_found}

      channels ->
        channel = hd(channels)
        {:ok, {channel.id, channel.display_name}}
    end
  end

  defp search_channel(:youtube, term) do
    case Youtube.search_channels(term) do
      channels when channels == [] ->
        {:error, :not_found}

      channels ->
        channel = hd(channels)
        {:ok, {channel.id, channel.snippet["title"]}}
    end
  end

  defp subscribe_to_service(:twitch, service_id) do
    event_subscription = Twitch.add_stream_webhook(service_id)
    event_subscription["id"]
  end

  defp subscribe_to_service(:youtube, service_id) do
    {:ok} = Youtube.manage_channel_pubsub(service_id, true)
    nil
  end
end
