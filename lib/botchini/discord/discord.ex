defmodule Botchini.Discord do
  @moduledoc """
  Handles discord context
  """

  require Logger
  require Ecto.Query
  alias Ecto.Query

  alias Nostrum.Api.Guild, as: GuildApi
  alias Nostrum.Error.ApiError

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo

  @spec count_guilds() :: integer()
  def count_guilds do
    Query.from(g in Guild, select: count())
    |> Repo.one!()
  end

  @doc """
  Whether the user is a member of the guild, asked to Discord as the bot. Anything
  but Discord saying the user isn't there is an error, so an outage doesn't lock members out
  as if they had left
  """
  @spec check_member(String.t(), String.t()) :: :member | :not_member | :error
  def check_member(guild_id, user_id) do
    case GuildApi.member(String.to_integer(guild_id), String.to_integer(user_id)) do
      {:ok, _member} ->
        :member

      {:error, %ApiError{status_code: 404}} ->
        :not_member

      {:error, error} ->
        Logger.warning("Failed to check a guild member", error: inspect(error))
        :error
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
