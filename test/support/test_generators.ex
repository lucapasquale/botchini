defmodule Botchini.TestGenerators do
  alias Botchini.Discord.Guild
  alias Botchini.Repo
  alias Botchini.Twitch.{Follower, Stream}

  @spec generate_guild() :: Guild.t()
  def generate_guild() do
    {:ok, guild} =
      %Guild{}
      |> Guild.changeset(%{discord_guild_id: Faker.String.base64()})
      |> Repo.insert()

    guild
  end

  @spec generate_stream() :: Stream.t()
  def generate_stream() do
    {:ok, stream} =
      %Stream{}
      |> Stream.changeset(%{
        code: String.downcase(Faker.String.base64()),
        twitch_user_id: Faker.String.base64(),
        twitch_subscription_id: Faker.String.base64()
      })
      |> Repo.insert()

    stream
  end

  @spec generate_follower(map()) :: Follower.t()
  def generate_follower(attrs \\ %{}) do
    payload =
      %{
        discord_channel_id: Faker.String.base64(),
        discord_user_id: Faker.String.base64()
      }
      |> Map.merge(attrs)

    {:ok, follower} =
      %Follower{}
      |> Follower.changeset(payload)
      |> Repo.insert()

    follower
  end
end
