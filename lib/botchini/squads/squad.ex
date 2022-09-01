defmodule Botchini.Squads do
  @moduledoc """
  Handles squads context
  """

  import Ecto.Query
  require Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Squads.Schema.{Squad, SquadMember}
  alias Botchini.Repo

  @spec get_by_id!(Guild.t(), String.t()) :: Squad.t()
  def get_by_id!(guild, id) do
    from(s in Squad,
      where: s.id == ^id,
      where: s.guild_id == ^guild.id
    )
    |> Repo.one!()
  end

  @spec search_by_term(Guild.t(), String.t()) :: Squad.t()
  def search_by_term(guild, term) do
    term = "%#{term}%"

    from(s in Squad,
      select: {s.id, s.name},
      where: ilike(s.name, ^term),
      where: s.guild_id == ^guild.id,
      limit: 5
    )
    |> Repo.all()
  end

  @spec insert(Guild.t(), %{name: String.t()}) :: {:ok, Squad.t()}
  def insert(guild, %{name: name}) do
    %Squad{}
    |> Squad.changeset(%{guild_id: guild.id, name: name})
    |> Repo.insert()
  end

  @spec all_members(Squad.t()) :: list(SquadMember.t())
  def all_members(squad) do
    from(s in SquadMember, where: s.squad_id == ^squad.id)
    |> Repo.all()
  end

  @spec insert_member(Squad.t(), %{discord_user_id: String.t()}) ::
          {:error, Ecto.Changeset.t()} | {:ok, Squad.t()}
  def insert_member(squad, %{discord_user_id: discord_user_id}) do
    %SquadMember{}
    |> SquadMember.changeset(%{discord_user_id: discord_user_id, squad_id: squad.id})
    |> Repo.insert()
  end

  @spec remove_member(Squad.t(), %{discord_user_id: String.t()}) ::
          {:error, :not_found} | {:ok, SquadMember.t()}
  def remove_member(squad, %{discord_user_id: discord_user_id}) do
    case Repo.get_by(SquadMember, squad_id: squad.id, discord_user_id: discord_user_id) do
      nil ->
        {:error, :not_found}

      member ->
        Repo.delete(member)
        {:ok, member}
    end
  end
end
