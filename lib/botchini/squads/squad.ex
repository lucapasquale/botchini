defmodule Botchini.Squads do
  @moduledoc """
  Handles squads context
  """

  require Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Squads.Schema.{Squad, SquadMember}
  alias Botchini.Repo

  @spec insert_squad(Guild.t(), %{name: String.t()}) :: {:ok, Squad.t()}
  def insert_squad(guild, %{name: name}) do
    %Squad{}
    |> Squad.changeset(%{guild_id: guild.id, name: name})
    |> Repo.insert()
  end

  @spec insert_member(Squad.t(), %{discord_user_id: String.t()}) :: {:ok, Squad.t()}
  def insert_member(squad, %{discord_user_id: discord_user_id}) do
    %SquadMember{}
    |> SquadMember.changeset(%{discord_user_id: discord_user_id, squad_id: squad.id})
    |> Repo.insert()
  end
end
