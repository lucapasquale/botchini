defmodule Botchini.Discord do
  @moduledoc """
  Handles discord context
  """

  require Logger
  require Ecto.Query
  alias Ecto.Query

  alias Nostrum.Api.Guild, as: GuildApi
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Error.ApiError
  alias Nostrum.Struct.Guild.Member

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo

  @spec count_guilds() :: integer()
  def count_guilds do
    Query.from(g in Guild, select: count())
    |> Repo.one!()
  end

  @doc """
  Whether the user is a member of the guild, asked to Discord as the bot, and `:admin`
  when they can manage it. Anything but Discord saying the user isn't there is an error,
  so an outage doesn't lock members out as if they had left
  """
  @spec check_member(String.t(), String.t()) :: :admin | :member | :not_member | :error
  def check_member(guild_id, user_id) do
    guild_id = String.to_integer(guild_id)

    case GuildApi.member(guild_id, String.to_integer(user_id)) do
      {:ok, member} ->
        if manage_guild?(guild_id, member), do: :admin, else: :member

      {:error, %ApiError{status_code: 404}} ->
        :not_member

      {:error, error} ->
        Logger.warning("Failed to check a guild member", error: inspect(error))
        :error
    end
  end

  @doc """
  Whether the member has the Manage Server permission, which administrators and
  the owner have too. It's worked out from the cached guild's roles
  """
  @spec manage_guild?(Nostrum.Snowflake.t(), Member.t()) :: boolean()
  def manage_guild?(guild_id, %Member{} = member) do
    case GuildCache.get(guild_id) do
      {:ok, guild} -> :manage_guild in Member.guild_permissions(member, guild)
      {:error, _reason} -> false
    end
  end

  @spec fetch_guild(String.t()) :: Guild.t()
  def fetch_guild(discord_guild_id) do
    Query.from(g in Guild, where: g.discord_guild_id == ^discord_guild_id)
    |> Repo.one!()
  end

  @spec upsert_guild(String.t()) :: {:ok, Guild.t()}
  def upsert_guild(discord_guild_id) do
    case Repo.get_by(Guild, discord_guild_id: discord_guild_id) do
      nil ->
        %Guild{}
        |> Guild.changeset(%{discord_guild_id: discord_guild_id})
        |> Repo.insert()

      guild ->
        {:ok, guild}
    end
  end
end
