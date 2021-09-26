defmodule Botchini.DataCase do
  @moduledoc """
  Case for tests that use the database
  """

  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo
  alias Botchini.Voice.Schema.Track
  alias Botchini.Twitch.Schema.{Follower, Stream}

  using do
    quote do
      import Ecto
      import Ecto.{Changeset, Query}

      import Botchini.DataCase
      alias Botchini.Repo
    end
  end

  setup tags do
    :ok = Sandbox.checkout(Repo)

    unless tags[:async] do
      Sandbox.mode(Repo, {:shared, self()})
    end

    :ok
  end

  @spec generate_guild(map()) :: Guild.t()
  def generate_guild(attrs \\ %{}) do
    payload =
      %{discord_guild_id: Faker.String.base64()}
      |> Map.merge(attrs)

    {:ok, guild} =
      %Guild{}
      |> Guild.changeset(payload)
      |> Repo.insert()

    guild
  end

  @spec generate_stream(map()) :: Stream.t()
  def generate_stream(attrs \\ %{}) do
    payload =
      %{
        code: String.downcase(Faker.String.base64()),
        twitch_user_id: Faker.String.base64(),
        twitch_subscription_id: Faker.String.base64()
      }
      |> Map.merge(attrs)

    {:ok, stream} =
      %Stream{}
      |> Stream.changeset(payload)
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

  @spec generate_track(map()) :: Track.t()
  def generate_track(attrs \\ %{}) do
    payload =
      %{
        play_url: Faker.String.base64(),
        status: :waiting
      }
      |> Map.merge(attrs)

    {:ok, track} =
      %Track{}
      |> Track.changeset(payload)
      |> Repo.insert()

    track
  end
end
