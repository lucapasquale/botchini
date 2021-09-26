defmodule Botchini.Voice do
  @moduledoc """
  Handles voice context
  """

  require Ecto.Query
  alias Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo
  alias Botchini.Voice.Schema.Track

  @spec get_current_track(Guild.t()) :: Track.t() | nil
  def get_current_track(guild) do
    Query.from(t in Track,
      where: t.guild_id == ^guild.id,
      where: t.status in [:playing, :paused],
      order_by: t.inserted_at
    )
    |> Repo.one()
  end

  @spec insert_track(String.t(), Guild.t()) :: {:ok, Track.t()}
  def insert_track(play_url, guild) do
    %Track{}
    |> Track.changeset(%{play_url: play_url, status: :waiting, guild_id: guild.id})
    |> Repo.insert()
  end

  @spec pause(Guild.t()) :: Track.t() | nil
  def pause(guild) do
    get_current_track(guild)
    |> update_track_status(:paused)
  end

  @spec resume(Guild.t()) :: Track.t() | nil
  def resume(guild) do
    get_current_track(guild)
    |> update_track_status(:playing)
  end

  @spec clear_queue(Guild.t()) :: any()
  def clear_queue(guild) do
    Query.from(t in Track, where: t.guild_id == ^guild.id)
    |> Repo.update_all(set: [status: :done])
  end

  @spec start_next_track(Guild.t()) :: Track.t() | nil
  def start_next_track(guild) do
    get_current_track(guild)
    |> update_track_status(:done)

    get_next_track(guild)
    |> update_track_status(:playing)
  end

  defp get_next_track(guild) do
    Query.from(t in Track,
      where: t.guild_id == ^guild.id,
      where: t.status == :waiting,
      order_by: t.inserted_at,
      limit: 1
    )
    |> Repo.all()
    |> List.first()
  end

  defp update_track_status(track, _status) when is_nil(track), do: nil

  defp update_track_status(track, status) do
    track
    |> Track.changeset(%{status: status})
    |> Repo.update!()
  end
end
