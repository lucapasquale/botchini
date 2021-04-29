defmodule Botchini.Guilds do
  alias Botchini.Repo
  alias Botchini.Guilds.Guild

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
