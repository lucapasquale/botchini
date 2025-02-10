defmodule Botchini.Creators do
  @moduledoc """
  Handles creators context
  """

  import Ecto.Query
  alias Ecto.Query

  alias Botchini.Creators.Schema.{Creator, Follower}
  alias Botchini.Discord.Schema.Guild
  alias Botchini.{Repo, Services}

  @type creator_input :: {Creator.services(), String.t()}

  @spec count_creators() :: integer()
  def count_creators do
    Query.from(s in Creator, select: count())
    |> Repo.one!()
  end

  @spec find_by_service(Creator.services(), String.t()) :: nil | Creator.t()
  def find_by_service(service, service_id) do
    from(c in Creator,
      where: c.service == ^service,
      where: c.service_id == ^service_id
    )
    |> Repo.one()
  end

  @spec find_all_for_service(Creator.services()) :: list(Creator.t())
  def find_all_for_service(service) do
    Creator
    |> Ecto.Query.where(service: ^service)
    |> Repo.all()
  end

  @spec find_followers_for_creator(Creator.t()) :: list(Follower.t())
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
      where: ilike(c.name, ^term),
      where: f.discord_channel_id == ^channel_id,
      limit: 5
    )
    |> Repo.all()
  end

  @spec upsert(Creator.services(), String.t()) :: {:error, :invalid_creator} | {:ok, Creator.t()}
  def upsert(service, service_id) do
    case Repo.get_by(Creator, service: service, service_id: service_id) do
      %Creator{} = existing ->
        {:ok, existing}

      nil ->
        insert_creator(service, service_id)
    end
  end

  defp insert_creator(service, service_id) do
    with {:ok, {^service_id, name}} <- Services.get_user(service, service_id),
         webhook_id <- Services.subscribe_to_service(service, service_id) do
      %Creator{}
      |> Creator.changeset(%{
        name: name,
        service: service,
        service_id: service_id,
        webhook_id: webhook_id
      })
      |> Repo.insert()
    else
      _ -> {:error, :invalid_creator}
    end
  end

  @spec follow(Creator.t(), Guild.t() | nil, %{
          channel_id: String.t(),
          user_id: String.t() | nil
        }) ::
          {:ok, Follower.t()} | {:error, :already_following}
  def follow(creator, guild, follower_info) do
    existing_follower =
      Repo.get_by(Follower,
        creator_id: creator.id,
        discord_channel_id: follower_info.channel_id
      )

    case existing_follower do
      nil ->
        %Follower{}
        |> Follower.changeset(%{
          creator_id: creator.id,
          guild_id: guild && guild.id,
          discord_user_id: follower_info.user_id,
          discord_channel_id: follower_info.channel_id
        })
        |> Repo.insert()

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
            remove_follower(creator, follower)
            {:ok, creator}
        end
    end
  end

  defp remove_follower(creator, follower) do
    Repo.delete(follower)

    remaining_followers =
      from(
        f in Follower,
        select: count(),
        where: f.creator_id == ^creator.id
      )
      |> Repo.one!()

    if remaining_followers == 0 do
      {:ok} =
        Services.unsubscribe_from_service(
          creator.service,
          {creator.service_id, creator.webhook_id}
        )

      Repo.delete(creator)
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
        select: {f.discord_channel_id, c.name}
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
        select: c.name,
        where: f.discord_channel_id == ^channel_id
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

  @spec discord_channel_follower(Creator.services(), String.t(), %{:channel_id => String.t()}) ::
          Follower.t() | nil
  def discord_channel_follower(service, service_id, %{channel_id: channel_id}) do
    from(
      c in Creator,
      join: f in Follower,
      on: f.creator_id == c.id,
      select: f,
      where: c.service == ^service,
      where: c.service_id == ^service_id,
      where: f.discord_channel_id == ^channel_id
    )
    |> Repo.one()
  end
end
