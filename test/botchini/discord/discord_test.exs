defmodule BotchiniTest.Discord.DiscordTest do
  use Botchini.DataCase, async: false

  alias Botchini.Discord

  describe "upsert_guild" do
    test "create new guild if doesnt exist" do
      discord_guild_id = Faker.String.base64()

      {:ok, guild} = Discord.upsert_guild(discord_guild_id)

      assert guild != nil
      assert guild.discord_guild_id == discord_guild_id
    end

    test "use existing stream" do
      existing_guild = generate_guild()

      {:ok, guild} = Discord.upsert_guild(existing_guild.discord_guild_id)

      assert guild == existing_guild
    end
  end
end
