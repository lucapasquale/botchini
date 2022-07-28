defmodule Botchini.DataCase do
  @moduledoc """
  Case for tests that use the database
  """

  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo
  alias Botchini.Creators.Schema.{Creator, Follower}
  alias Botchini.Services.Schema.Video

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

  @spec generate_creator(map()) :: Creator.t()
  def generate_creator(attrs \\ %{}) do
    payload =
      %{
        service: Faker.Util.pick([:twitch, :youtube]),
        name: Faker.String.base64(),
        service_id: Faker.String.base64(),
        webhook_id: Faker.String.base64()
      }
      |> Map.merge(attrs)

    {:ok, creator} =
      %Creator{}
      |> Creator.changeset(payload)
      |> Repo.insert()

    creator
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

  @spec generate_video(map()) :: Video.t()
  def generate_video(attrs \\ %{}) do
    payload =
      %{
        channel_id: Faker.String.base64(),
        video_id: Faker.String.base64()
      }
      |> Map.merge(attrs)

    {:ok, video} =
      %Video{}
      |> Video.changeset(payload)
      |> Repo.insert()

    video
  end
end
