defmodule Botchini.Voice do
  @moduledoc """
  Handles voice context
  """

  require Ecto.Query

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo
  alias Botchini.Voice.Schema.Track

  @spec insert_track(String.t(), Guild.t()) :: {:ok, Track.t()}
  def insert_track(play_url, guild) do
    %Track{}
    |> Track.changeset(%{play_url: play_url, status: :waiting, guild_id: guild.id})
    |> Repo.insert()
  end

  @spec clear_queue(Guild.t()) :: any()
  def clear_queue(guild) do
    Ecto.Query.from(t in Track, where: t.guild_id == ^guild.id)
    |> Repo.update_all(set: [status: :done])
  end

  @spec start_next_track(Guild.t()) :: Track.t() | nil
  def start_next_track(guild) do
    Track
    |> Ecto.Query.where(guild_id: ^guild.id)
    |> Ecto.Query.where(status: :playing)
    |> Ecto.Query.order_by(asc: :inserted_at)
    |> Repo.one()
    |> update_track_status(:done)

    next_track_in_queue(guild)
    |> update_track_status(:playing)
  end

  defp next_track_in_queue(guild) do
    Track
    |> Ecto.Query.where(guild_id: ^guild.id)
    |> Ecto.Query.where(status: :waiting)
    |> Ecto.Query.order_by(asc: :inserted_at)
    |> Ecto.Query.limit(1)
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
