defmodule Botchini.Twitch do
  @moduledoc """
  Handles business logic for twitch streams
  """

  alias Botchini.Repo
  alias Botchini.Guilds.Guild
  alias Botchini.Twitch.API
  alias Botchini.Twitch.{Stream, Follower}

  @spec follow_stream(String.t(), Guild.t(), %{channel_id: String.t(), user_id: String.t()}) ::
          {:ok, Stream.t()} | {:error, :invalid_stream} | {:error, :already_following}
  def follow_stream(code, guild, follower_info) do
    case upsert_stream(code) do
      {:error, _} ->
        {:error, :invalid_stream}

      {:ok, stream} ->
        existing_follower =
          Repo.get_by(Follower,
            stream_id: stream.id,
            discord_channel_id: follower_info.channel_id
          )

        case existing_follower do
          nil ->
            insert_follower(stream, guild, follower_info)
            {:ok, stream}

          _follower ->
            {:error, :already_following}
        end
    end
  end

  defp upsert_stream(code) do
    case Repo.get_by(Stream, code: code) do
      %Stream{} = existing ->
        {:ok, existing}

      nil ->
        case API.get_user(code) do
          nil ->
            {:error, :invalid_stream}

          twitch_user ->
            event_subscription = API.add_stream_webhook(twitch_user["id"])

            %Stream{}
            |> Stream.changeset(%{
              code: code,
              twitch_user_id: twitch_user["id"],
              twitch_subscription_id: event_subscription["id"]
            })
            |> Repo.insert()
        end
    end
  end

  defp insert_follower(stream, guild, %{channel_id: channel_id, user_id: user_id}) do
    %Follower{}
    |> Follower.changeset(%{
      guild_id: guild.id,
      stream_id: stream.id,
      discord_user_id: user_id,
      discord_channel_id: channel_id
    })
    |> Repo.insert!()
  end
end
