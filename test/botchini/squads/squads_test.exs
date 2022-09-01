defmodule BotchiniTest.Squads.SquadsTest do
  use Botchini.DataCase, async: false

  alias Botchini.Squads
  alias Botchini.Squads.Schema.SquadMember

  describe "get_by_id!" do
    test "gets a squad by guild and id" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})

      assert Squads.get_by_id!(guild, squad.id) == squad
    end

    test "throws if uses an invalid id" do
      guild = generate_guild()

      assert_raise Ecto.NoResultsError, fn ->
        Squads.get_by_id!(guild, Faker.random_between(999_999, 9_999_999))
      end
    end

    test "throws if uses a different guild" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})

      other_guild = generate_guild()

      assert_raise Ecto.NoResultsError, fn ->
        Squads.get_by_id!(other_guild, squad.id)
      end
    end
  end

  describe "searh_by_term" do
    test "returns all squads if term is empty" do
      guild = generate_guild()
      generate_squad(%{guild_id: guild.id})
      generate_squad(%{guild_id: guild.id})
      generate_squad(%{guild_id: guild.id})

      assert length(Squads.search_by_term(guild, "")) == 3
    end

    test "returns all squads with name that matches term" do
      guild = generate_guild()
      generate_squad(%{guild_id: guild.id, name: "Test1"})
      generate_squad(%{guild_id: guild.id, name: "SOMETHING_ELSE"})
      generate_squad(%{guild_id: guild.id, name: "Test2"})

      assert length(Squads.search_by_term(guild, "test")) == 2
    end
  end

  describe "insert" do
    test "can insert a squad" do
      guild = generate_guild()

      name = Faker.String.base64()
      {:ok, squad} = Squads.insert(guild, %{name: name})

      assert squad.id
      assert squad.name == name
      assert squad.guild_id == guild.id
    end
  end

  describe "all_members" do
    test "can get all members in a squad" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})

      generate_squad_member(%{squad_id: squad.id})
      generate_squad_member(%{squad_id: squad.id})

      other_squad = generate_squad(%{guild_id: guild.id})
      generate_squad_member(%{squad_id: other_squad.id})

      assert length(Squads.all_members(squad)) == 2
    end
  end

  describe "insert_member" do
    test "can get all members in a squad" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})

      discord_user_id = Faker.String.base64()
      {:ok, member} = Squads.insert_member(squad, %{discord_user_id: discord_user_id})

      assert member.id
      assert member.squad_id == squad.id
      assert member.discord_user_id == discord_user_id
    end

    test "returns :error if inserts member into squad again" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})
      member = generate_squad_member(%{squad_id: squad.id})

      {:error, _} = Squads.insert_member(squad, %{discord_user_id: member.discord_user_id})
    end
  end

  describe "remove_member" do
    test "removes member from squad" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})
      member = generate_squad_member(%{squad_id: squad.id})

      {:ok, ^member} = Squads.remove_member(squad, %{discord_user_id: member.discord_user_id})

      refute Repo.get(SquadMember, member.id)
    end

    test "returns :error if member not found" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})

      {:error, _} = Squads.remove_member(squad, %{discord_user_id: Faker.String.base64()})
    end

    test "returns :error if squad not found" do
      guild = generate_guild()
      squad = generate_squad(%{guild_id: guild.id})
      member = generate_squad_member(%{squad_id: squad.id})

      {:error, _} =
        Squads.remove_member(%{id: Faker.random_between(999_999, 9_999_999)}, %{
          discord_user_id: member.discord_user_id
        })
    end
  end
end
