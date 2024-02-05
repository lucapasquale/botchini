defmodule Botchini.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Botchini.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  alias Botchini.Discord.Schema.Guild
  alias Botchini.Repo
  alias Botchini.Creators.Schema.{Creator, Follower}
  alias Botchini.Squads.Schema.{Squad, SquadMember}

  using do
    quote do
      alias Botchini.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Botchini.DataCase
    end
  end

  setup tags do
    Botchini.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Botchini.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
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

  @spec generate_squad(map()) :: Squad.t()
  def generate_squad(attrs \\ %{}) do
    payload =
      %{
        name: Faker.String.base64()
      }
      |> Map.merge(attrs)

    {:ok, squad} =
      %Squad{}
      |> Squad.changeset(payload)
      |> Repo.insert()

    squad
  end

  @spec generate_squad_member(map()) :: SquadMember.t()
  def generate_squad_member(attrs \\ %{}) do
    payload =
      %{
        discord_user_id: Faker.String.base64()
      }
      |> Map.merge(attrs)

    {:ok, member} =
      %SquadMember{}
      |> SquadMember.changeset(payload)
      |> Repo.insert()

    member
  end
end
