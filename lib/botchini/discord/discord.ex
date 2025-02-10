defmodule Botchini.Discord do
  @moduledoc """
  Handles discord context
  """

  require Ecto.Query
  alias Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo

  @spec count_guilds() :: integer()
  def count_guilds do
    Query.from(g in Guild, select: count())
    |> Repo.one!()
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
