defmodule Botchini.Music do
  @moduledoc """
  Handles music context
  """

  require Ecto.Query
  alias Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Music.Schema.Track
  alias Botchini.Repo

  @spec get_current_track(Guild.t()) :: Track.t() | nil
  def get_current_track(guild) do
    Query.from(t in Track,
      where: t.guild_id == ^guild.id,
      where: t.status in [:playing, :paused]
    )
    |> Repo.one()
  end

  @spec get_next_track(Guild.t()) :: Track.t() | nil
  def get_next_track(guild) do
    Query.from(t in Track,
      where: t.guild_id == ^guild.id,
      where: t.status == :waiting,
      order_by: t.inserted_at,
      limit: 1
    )
    |> Repo.all()
    |> List.first()
  end

  @spec get_next_tracks(Guild.t()) :: list(Track.t())
  def get_next_tracks(guild) do
    Query.from(t in Track,
      where: t.guild_id == ^guild.id,
      where: t.status == :waiting,
      order_by: t.inserted_at,
      limit: 10
    )
    |> Repo.all()
  end

  @spec insert_track(
          %{term: String.t(), play_url: String.t(), play_type: :ytdl | :stream},
          Guild.t()
        ) :: {:ok, Track.t()}
  def insert_track(%{term: term, play_url: play_url, play_type: play_type}, guild) do
    %Track{}
    |> Track.changeset(%{
      guild_id: guild.id,
      status: :waiting,
      title: term,
      play_url: play_url,
      play_type: play_type
    })
    |> Repo.insert!()
  end

  @spec start_next_track(Guild.t()) :: {:ok, Track.t() | nil}
  def start_next_track(guild) do
    get_current_track(guild)
    |> update_track_status(:done)

    get_next_track(guild)
    |> update_track_status(:playing)
  end

  @spec pause(Guild.t()) :: {:ok, Track.t() | nil}
  def pause(guild) do
    get_current_track(guild)
    |> update_track_status(:paused)
  end

  @spec resume(Guild.t()) :: {:ok, Track.t() | nil}
  def resume(guild) do
    get_current_track(guild)
    |> update_track_status(:playing)
  end

  @spec clear_queue(Guild.t()) :: {non_neg_integer(), any()}
  def clear_queue(guild) do
    Query.from(t in Track,
      where: t.guild_id == ^guild.id,
      where: t.status != :done
    )
    |> Repo.update_all(set: [status: :done])
  end

  defp update_track_status(track, _status) when is_nil(track), do: {:ok, nil}

  defp update_track_status(track, status) do
    track
    |> Track.changeset(%{status: status})
    |> Repo.update()
  end
end
