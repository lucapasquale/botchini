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
      where: fragment("metadata->>'user_id' = ?", ^twitch_user_id)
    )
    |> Repo.one()
  end

  @spec find_followers_for_creator(Creator.t()) :: [Follower.t()]
  def find_followers_for_creator(creator) do
    Follower
    |> Ecto.Query.where(creator_id: ^creator.id)
    |> Repo.all()
  end

  @spec search_following_creators(String.t(), %{channel_id: String.t()}) :: [Creator.t()]
  def search_following_creators(term, %{channel_id: channel_id}) do
    term = "%#{term}%"

    from(
      c in Creator,
      join: f in Follower,
      on: f.creator_id == c.id,
      where: ilike(c.code, ^term),
      where: f.discord_channel_id == ^channel_id,
      limit: 5
    )
    |> Repo.all()
  end

  @spec follow_creator(creator_input, Guild.t() | nil, %{
          channel_id: String.t(),
          user_id: String.t() | nil
        }) ::
          {:ok, Creator.t()} | {:error, :invalid_creator} | {:error, :already_following}
  def follow_creator({service, code}, guild, follower_info) do
    case upsert_creator({service, code}) do
      {:error, _} ->
        {:error, :invalid_creator}

      {:ok, creator} ->
        existing_follower =
          Repo.get_by(Follower,
            creator_id: creator.id,
            discord_channel_id: follower_info.channel_id
          )

        case existing_follower do
          nil ->
            insert_follower(creator, guild, follower_info)
            {:ok, creator}

          _follower ->
            {:error, :already_following}
        end
    end
  end

  @spec unfollow(creator_input, %{channel_id: String.t()}) ::
          {:ok} | {:error, :not_found}
  def unfollow({service, code}, %{channel_id: channel_id}) do
    case Repo.get_by(Creator, service: service, code: code) do
      nil ->
        {:error, :not_found}

      creator ->
        existing_follower =
          Repo.get_by(Follower,
            creator_id: creator.id,
            discord_channel_id: channel_id
          )

        case existing_follower do
          nil ->
            {:error, :not_found}

          follower ->
            unfollow_creator(creator, follower)
            {:ok}
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

  @spec channel_follower(creator_input, %{channel_id: String.t()}) ::
          {:error, :not_found} | {:ok, Follower.t()}
  def channel_follower({service, code}, %{channel_id: channel_id}) do
    case Repo.get_by(Creator, service: service, code: code) do
      nil ->
        {:error, :not_found}

      creator ->
        case Repo.get_by(Follower, creator_id: creator.id, discord_channel_id: channel_id) do
          nil ->
            {:error, :not_found}

          follower ->
            {:ok, follower}
        end
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

  @spec youtube_channel_info(String.t()) ::
          {:error, :not_found} | {:ok, Youtube.Structs.Channel.t()}
  def youtube_channel_info(code) do
    case Youtube.get_channel(code) do
      nil -> {:error, :not_found}
      channel -> {:ok, channel}
    end
  end

  defp upsert_creator({service, code}) do
    case Repo.get_by(Creator, service: service, code: code) do
      %Creator{} = existing ->
        {:ok, existing}

      nil ->
        case Twitch.get_user(code) do
          nil ->
            {:error, :invalid_stream}

          user ->
            event_subscription = Twitch.add_stream_webhook(user.id)

            %Creator{}
            |> Creator.changeset(%{
              service: :twitch,
              code: code,
              name: user.display_name,
              metadata: %{
                user_id: user.id,
                subscription_id: event_subscription["id"]
              }
            })
            |> Repo.insert()
        end
    end
  end

  defp insert_follower(creator, guild, %{channel_id: channel_id, user_id: user_id}) do
    %Follower{}
    |> Follower.changeset(%{
      creator_id: creator.id,
      guild_id: guild && guild.id,
      discord_user_id: user_id,
      discord_channel_id: channel_id
    })
    |> Repo.insert!()
  end

  defp unfollow_creator(creator, follower) do
    Repo.delete(follower)

    remaining_followers =
      Ecto.Query.where(Follower, creator_id: ^creator.id)
      |> Repo.all()

    if remaining_followers == [] do
      Twitch.delete_stream_webhook(creator.metadata["subscription_id"])
      Repo.delete(creator)
    end
  end
end
